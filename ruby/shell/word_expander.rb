require "shellwords"
require "open3"
require "shell/quote_cursor"
require "shell/string_parser"

module Shell
  class WordExpander
    ENV_VAR_REGEX = /\$(?:\{([^}]+)\}|(\w+)\b)/
    DEFAULT_VAR_REGEX = /\A(\w+):-([\s\S]*)\z/
    ESCAPED_DOLLAR = "\u0001"
    ESCAPED_BACKTICK = "\u0002"

    # Splits the given line into multiple words, performing the following transformations:
    #
    # - Splits into words taking quoting and backslash escaping into account
    # - Expands environment variables using $NAME and ${NAME} syntax
    # - Tilde expansion, which means that ~ is expanded to $HOME
    # - Glob expansion on files and directories
    def expand(line)
      protected_line = protect_escaped_dollars(line)
      substituted_line = expand_command_substitution(protected_line)
      shellsplit(substituted_line)
        .flat_map do |word|
          expanded = expand_variables(word)
            .tr(ESCAPED_DOLLAR, "$")
            .tr(ESCAPED_BACKTICK, "`")
          expand_braces(expanded)
        end
    end

    # Lifted directly from Ruby 4.0.0.
    #
    # Splits a string into an array of tokens in the same way the UNIX
    # Bourne shell does.
    #
    #   argv = Shellwords.split('here are "two words"')
    #   argv #=> ["here", "are", "two words"]
    #
    # +line+ must not contain NUL characters because of nature of
    # +exec+ system call.
    #
    # Note, however, that this is not a command line parser.  Shell
    # metacharacters except for the single and double quotes and
    # backslash are not treated as such.
    #
    #   argv = Shellwords.split('ruby my_prog.rb | less')
    #   argv #=> ["ruby", "my_prog.rb", "|", "less"]
    #
    # String#shellsplit is a shortcut for this function.
    #
    #   argv = 'here are "two words"'.shellsplit
    #   argv #=> ["here", "are", "two words"]
    def shellsplit(line)
      words = []
      field = "".dup
      at_word_start = true
      found_glob_char = false
      line.scan(/\G\s*(?>([^\0\s\\'"]+)|'([^\0']*)'|"((?:[^\0"\\]|\\[^\0])*)"|(\\[^\0]?)|(\S))(\s|\z)?/m) do |word, sq, dq, esc, garbage, sep|
        if garbage
          b = $~.begin(0)
          line = $~[0]
          line = "..." + line if b > 0
          raise ArgumentError, "#{(garbage == "\0") ? "Nul character" : "Unmatched quote"} at #{b}: #{line}"
        end
        # 2.2.3 Double-Quotes:
        #
        #   The <backslash> shall retain its special meaning as an
        #   escape character only when followed by one of the following
        #   characters when considered special:
        #
        #   $ ` " \ <newline>
        field << (word || sq || (dq && dq.gsub(/\\([$`"\\\n])/, '\\1')) || esc.gsub(/\\(.)/, '\\1'))
        found_glob_char = word && word =~ /[*?\[]/ # must be unquoted
        # Expand tildes at the beginning of unquoted words.
        if word && at_word_start
          field.sub!(/^~([^\/]*)/) do
            user = Regexp.last_match(1)
            user.empty? ? Dir.home : Dir.home(user)
          rescue ArgumentError
            "~#{user}"
          end
        end
        at_word_start = false
        if sep
          if found_glob_char
            glob_words = expand_globs(field)
            words += (glob_words.empty? ? [field] : glob_words)
          else
            words << field
          end
          field = "".dup
          at_word_start = true
          found_glob_char = false
        end
      end
      words
    end

    def expand_globs(word)
      Dir.glob(word)
    end

    def expand_variables(value)
      value.gsub(ENV_VAR_REGEX) do
        raw = Regexp.last_match(2) || Regexp.last_match(1)
        if (m = DEFAULT_VAR_REGEX.match(raw))
          name = m[1]
          fallback = m[2]
          env_value = ENV[name]
          (env_value.nil? || env_value.empty?) ? expand_variables(fallback) : env_value
        else
          ENV.fetch(raw)
        end
      end
    end

    def expand_command_substitution(line)
      output = +""
      i = 0
      cursor = QuoteCursor.new
      while i < line.length
        c = line[i]
        if cursor.unquoted?
          case c
          when "`"
            cmd, i = read_backtick(line, i + 1)
            output << escape_substitution_output(run_command_substitution(cmd), :unquoted)
          when "$"
            if line[i + 1] == "("
              if line[i + 2] == "("
                expr, i = read_arithmetic(line, i + 3)
                output << expand_arithmetic(expr)
              else
                cmd, i = read_dollar_paren(line, i + 2)
                output << escape_substitution_output(run_command_substitution(cmd), :unquoted)
              end
            else
              output << c
              i += 1
            end
          when "\\"
            if i + 1 < line.length
              escaped = line[i + 1]
              if escaped == "$"
                output << ESCAPED_DOLLAR
                i += 2
              elsif escaped == "`"
                output << ESCAPED_BACKTICK
                i += 2
              else
                segment, i = cursor.consume(line, i)
                output << segment
              end
            else
              segment, i = cursor.consume(line, i)
              output << segment
            end
          else
            segment, i = cursor.consume(line, i)
            output << segment
          end

        elsif cursor.state == :double_quoted
          case c
          when "\\"
            if i + 1 < line.length
              escaped = line[i + 1]
              if escaped == "$" || escaped == "`"
                output << escaped_replacement(escaped)
              else
                output << "\\"
                output << escaped
              end
              i += 2
            else
              segment, i = cursor.consume(line, i)
              output << segment
            end
          when "`"
            cmd, i = read_backtick(line, i + 1)
            output << escape_substitution_output(run_command_substitution(cmd), :double_quoted)
          when "$"
            if line[i + 1] == "("
              if line[i + 2] == "("
                expr, i = read_arithmetic(line, i + 3)
                output << expand_arithmetic(expr)
              else
                cmd, i = read_dollar_paren(line, i + 2)
                output << escape_substitution_output(run_command_substitution(cmd), :double_quoted)
              end
            else
              segment, i = cursor.consume(line, i)
              output << segment
            end
          else
            segment, i = cursor.consume(line, i)
            output << segment
          end

        else
          segment, i = cursor.consume(line, i)
          output << segment
        end
      end
      output
    end

    def read_backtick(line, start_index)
      output = +""
      i = start_index
      while i < line.length
        c = line[i]
        if c == "`"
          return [output, i + 1]
        end
        if c == "\\"
          if i + 1 < line.length
            output << line[i + 1]
            i += 2
            next
          end
        end
        output << c
        i += 1
      end
      raise ArgumentError, "Unmatched backtick"
    end

    def read_dollar_paren(line, start_index)
      StringParser.read_dollar_paren(line, start_index)
    end

    def read_arithmetic(line, start_index)
      output = +""
      i = start_index
      depth = 1
      while i < line.length
        c = line[i]
        if c == "("
          depth += 1
          output << c
        elsif c == ")"
          depth -= 1
          if depth.zero?
            if line[i + 1] == ")"
              return [output, i + 2]
            else
              depth += 1
              output << c
            end
          else
            output << c
          end
        else
          output << c
        end
        i += 1
      end
      raise ArgumentError, "Unmatched $((...))"
    end

    def run_command_substitution(command)
      stdout, status = Open3.capture2("/bin/sh", "-c", command)
      raise Errno::ENOENT, command unless status.success?
      stdout = stdout.sub(/\n+\z/, "")
      stdout.tr("\n", " ")
    end

    def escape_substitution_output(value, context)
      escaped = value.gsub("$", ESCAPED_DOLLAR)
      case context
      when :double_quoted
        escaped.gsub(/([\\"])/, '\\\\\1')
      when :unquoted
        escaped.gsub(/(\\|["'])/, '\\\\\1')
      else
        escaped
      end
    end

    def expand_arithmetic(expr)
      tokens = tokenize_arithmetic(expr)
      rpn = arithmetic_to_rpn(tokens)
      evaluate_rpn(rpn).to_s
    end

    def tokenize_arithmetic(expr)
      tokens = []
      i = 0
      while i < expr.length
        c = expr[i]
        if c.match?(/\s/)
          i += 1
          next
        end
        if c.match?(/\d/)
          j = i + 1
          j += 1 while j < expr.length && expr[j].match?(/\d/)
          tokens << [:number, expr[i...j].to_i]
          i = j
          next
        end
        if c.match?(/[A-Za-z_]/)
          j = i + 1
          j += 1 while j < expr.length && expr[j].match?(/[A-Za-z0-9_]/)
          name = expr[i...j]
          value = ENV[name]
          value = (value.nil? || value.empty?) ? 0 : value.to_i
          tokens << [:number, value]
          i = j
          next
        end
        if c.match?(%r{[+\-*/()%]})
          tokens << [:op, c]
          i += 1
          next
        end
        raise ArgumentError, "Invalid arithmetic expression: #{expr}"
      end
      tokens
    end

    def arithmetic_to_rpn(tokens)
      output = []
      ops = []
      prev_type = nil
      tokens.each do |type, value|
        if type == :number
          output << [:number, value]
          prev_type = :number
          next
        end

        op = value
        if op == "("
          ops << op
          prev_type = :lparen
          next
        end
        if op == ")"
          while (top = ops.pop)
            break if top == "("
            output << [:op, top]
          end
          raise ArgumentError, "Unmatched ) in arithmetic expression" if top != "("
          prev_type = :rparen
          next
        end

        if op == "-" && (prev_type.nil? || prev_type == :op || prev_type == :lparen)
          op = "u-"
        elsif op == "+" && (prev_type.nil? || prev_type == :op || prev_type == :lparen)
          op = "u+"
        end

        while !ops.empty? && precedence(ops.last) >= precedence(op)
          output << [:op, ops.pop]
        end
        ops << op
        prev_type = :op
      end

      while (top = ops.pop)
        raise ArgumentError, "Unmatched ( in arithmetic expression" if top == "("
        output << [:op, top]
      end
      output
    end

    def precedence(op)
      case op
      when "u+", "u-"
        3
      when "*", "/", "%"
        2
      when "+", "-"
        1
      else
        0
      end
    end

    def evaluate_rpn(rpn)
      stack = []
      rpn.each do |type, value|
        if type == :number
          stack << value
          next
        end

        case value
        when "u+"
          raise ArgumentError, "Invalid arithmetic expression" if stack.empty?
          stack << stack.pop
        when "u-"
          raise ArgumentError, "Invalid arithmetic expression" if stack.empty?
          stack << -stack.pop
        else
          b = stack.pop
          a = stack.pop
          raise ArgumentError, "Invalid arithmetic expression" if a.nil? || b.nil?
          stack << apply_operator(a, b, value)
        end
      end
      raise ArgumentError, "Invalid arithmetic expression" unless stack.length == 1
      stack[0]
    end

    def apply_operator(a, b, op)
      case op
      when "+"
        a + b
      when "-"
        a - b
      when "*"
        a * b
      when "/"
        (b == 0) ? 0 : a / b
      when "%"
        (b == 0) ? 0 : a % b
      else
        raise ArgumentError, "Invalid arithmetic expression"
      end
    end

    def expand_braces(word)
      # Simple, non-nested brace expansion: pre{a,b}post -> preapost, prebpost
      match = word.match(/(.*?)\{([^{}]*)\}(.*)/)
      return [word] unless match

      prefix = match[1]
      body = match[2]
      suffix = match[3]
      return [word] unless body.include?(",")

      parts = body.split(",", -1)
      parts.flat_map { |part| expand_braces(prefix + part + suffix) }
    end

    def escaped_replacement(char)
      case char
      when "$"
        ESCAPED_DOLLAR
      when "`"
        ESCAPED_BACKTICK
      else
        char
      end
    end

    def protect_escaped_dollars(line)
      output = +""
      i = 0
      while i < line.length
        if line.getbyte(i) == "\\".ord
          j = i + 1
          j += 1 while j < line.length && line.getbyte(j) == "\\".ord
          count = j - i
          if j < line.length && line.getbyte(j) == "$".ord && count.odd?
            output << ("\\" * (count - 1))
            output << ESCAPED_DOLLAR
            i = j + 1
          else
            output << ("\\" * count)
            i = j
          end
        else
          output << line[i]
          i += 1
        end
      end
      output
    end
  end
end
