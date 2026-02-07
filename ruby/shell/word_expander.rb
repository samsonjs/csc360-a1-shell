require "open3"
require "shell/quote_cursor"
require "shell/string_parser"

module Shell
  class WordExpander
    ESCAPED_DOLLAR = "\u0001"
    ESCAPED_BACKTICK = "\u0002"
    GLOB_PATTERN = /[*?\[]/
    SHELLSPLIT_PATTERN = /\G\s*(?>([^\0\s\\'"]+)|'([^\0']*)'|"((?:[^\0"\\]|\\[^\0])*)"|(\\[^\0]?)|(\S))(\s|\z)?/m
    DOUBLE_QUOTE_ESCAPES_PATTERN = /\\([$`"\\\n])/
    SINGLE_ESCAPE_PATTERN = /\\(.)/
    TILDE_PREFIX_PATTERN = /^~([^\/]*)/
    VARIABLE_FIRST_CHAR_PATTERN = /[A-Za-z_]/
    VARIABLE_CHAR_PATTERN = /[A-Za-z0-9_]/
    TRAILING_NEWLINES_PATTERN = /\n+\z/
    ESCAPE_DOUBLE_QUOTED_SUBSTITUTION_PATTERN = /([\\"])/
    ESCAPE_UNQUOTED_SUBSTITUTION_PATTERN = /(\\|["'])/
    WHITESPACE_PATTERN = /\s/
    DIGIT_PATTERN = /\d/
    ARITHMETIC_IDENTIFIER_FIRST_PATTERN = /[A-Za-z_]/
    ARITHMETIC_IDENTIFIER_PATTERN = /[A-Za-z0-9_]/
    ARITHMETIC_OPERATOR_PATTERN = %r{[+\-*/()%]}
    BRACE_EXPANSION_PATTERN = /(.*?)\{([^{}]*)\}(.*)/
    SplitWord = Data.define(:text, :globbed)
    CommandSubstitutionError = Class.new(StandardError)

    # Splits the given line into multiple words, performing the following transformations:
    #
    # - Splits into words taking quoting and backslash escaping into account
    # - Expands environment variables using $NAME and ${NAME} syntax
    # - Tilde expansion, which means that ~ is expanded to $HOME
    # - Glob expansion on files and directories
    def expand(line)
      protected_line = protect_escaped_dollars(line)
      substituted_line = expand_command_substitution(protected_line)
      shellsplit_tokens(substituted_line)
        .flat_map do |word|
          expanded = expand_variables(word.text)
            .tr(ESCAPED_DOLLAR, "$")
            .tr(ESCAPED_BACKTICK, "`")
          expand_braces(expanded).map { SplitWord.new(text: it, globbed: word.globbed) }
        end
        .flat_map do |word|
          if word.globbed
            [word.text]
          elsif GLOB_PATTERN.match?(word.text)
            glob_words = expand_globs(word.text)
            glob_words.empty? ? [word.text] : glob_words
          else
            [word.text]
          end
        end
    end

    # Adapted from Ruby's Shellwords splitting logic.
    #
    # Splits a string into an array of tokens in the same way the UNIX
    # Bourne shell does.
    #
    #   argv = shellsplit('here are "two words"')
    #   argv #=> ["here", "are", "two words"]
    #
    # +line+ must not contain NUL characters because of nature of
    # +exec+ system call.
    #
    # Note, however, that this is not a command line parser.  Shell
    # metacharacters except for the single and double quotes and
    # backslash are not treated as such.
    #
    #   argv = shellsplit('ruby my_prog.rb | less')
    #   argv #=> ["ruby", "my_prog.rb", "|", "less"]
    #
    # String#shellsplit is a shortcut for this function.
    #
    #   argv = 'here are "two words"'.shellsplit
    #   argv #=> ["here", "are", "two words"]
    def shellsplit(line)
      shellsplit_tokens(line).map(&:text)
    end

    def shellsplit_tokens(line)
      words = []
      field = "".dup
      at_word_start = true
      found_glob_char = false
      line.scan(SHELLSPLIT_PATTERN) do |word, sq, dq, esc, garbage, sep|
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
        field << (word || sq || (dq && dq.gsub(DOUBLE_QUOTE_ESCAPES_PATTERN, '\\1')) || esc.gsub(SINGLE_ESCAPE_PATTERN, '\\1'))
        found_glob_char = word&.match?(GLOB_PATTERN) # must be unquoted
        # Expand tildes at the beginning of unquoted words.
        if word && at_word_start
          field.sub!(TILDE_PREFIX_PATTERN) do
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
            if glob_words.empty?
              words << SplitWord.new(text: field, globbed: false)
            else
              glob_words.each { words << SplitWord.new(text: it, globbed: true) }
            end
          else
            words << SplitWord.new(text: field, globbed: false)
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
      output = +""
      i = 0
      while i < value.length
        if value[i] != "$"
          output << value[i]
          i += 1
          next
        end

        if value[i + 1] == "{"
          raw, i = read_braced_variable(value, i + 2)
          output << resolve_braced_variable(raw)
        elsif variable_char?(value[i + 1], first: true)
          j = i + 2
          j += 1 while j < value.length && variable_char?(value[j], first: false)
          output << ENV.fetch(value[(i + 1)...j])
          i = j
        else
          output << "$"
          i += 1
        end
      end
      output
    end

    def read_braced_variable(value, start_index)
      output = +""
      depth = 1
      i = start_index
      while i < value.length
        c = value[i]
        if c == "{"
          depth += 1
        elsif c == "}"
          depth -= 1
          return [output, i + 1] if depth.zero?
        end
        output << c
        i += 1
      end
      raise ArgumentError, "Unmatched ${...}"
    end

    def resolve_braced_variable(raw)
      name, fallback = split_default_expression(raw)
      if fallback
        env_value = ENV[name]
        (env_value.nil? || env_value.empty?) ? expand_variables(fallback) : env_value
      else
        ENV.fetch(name)
      end
    end

    def split_default_expression(raw)
      depth = 0
      i = 0
      while i < raw.length - 1
        c = raw[i]
        if c == "{"
          depth += 1
        elsif c == "}"
          depth -= 1 if depth > 0
        elsif depth.zero? && c == ":" && raw[i + 1] == "-"
          return [raw[0...i], raw[(i + 2)..]]
        end
        i += 1
      end
      [raw, nil]
    end

    def variable_char?(char, first:)
      return false if char.nil?
      first ? VARIABLE_FIRST_CHAR_PATTERN.match?(char) : VARIABLE_CHAR_PATTERN.match?(char)
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
      stdout, stderr, status = Open3.capture3("/bin/sh", "-c", command)
      unless status.success?
        reason = status.exitstatus ? "exit #{status.exitstatus}" : "signal #{status.termsig}"
        details = stderr.to_s.strip
        message = "command substitution failed (#{reason}): #{command}"
        message = "#{message}: #{details}" unless details.empty?
        raise CommandSubstitutionError, message
      end
      stdout = stdout.sub(TRAILING_NEWLINES_PATTERN, "")
      stdout.tr("\n", " ")
    end

    def escape_substitution_output(value, context)
      escaped = value.gsub("$", ESCAPED_DOLLAR)
      case context
      when :double_quoted
        escaped.gsub(ESCAPE_DOUBLE_QUOTED_SUBSTITUTION_PATTERN, '\\\\\1')
      when :unquoted
        escaped.gsub(ESCAPE_UNQUOTED_SUBSTITUTION_PATTERN, '\\\\\1')
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
        if c.match?(WHITESPACE_PATTERN)
          i += 1
          next
        end
        if c.match?(DIGIT_PATTERN)
          j = i + 1
          j += 1 while j < expr.length && expr[j].match?(DIGIT_PATTERN)
          tokens << [:number, expr[i...j].to_i]
          i = j
          next
        end
        if c.match?(ARITHMETIC_IDENTIFIER_FIRST_PATTERN)
          j = i + 1
          j += 1 while j < expr.length && expr[j].match?(ARITHMETIC_IDENTIFIER_PATTERN)
          name = expr[i...j]
          value = ENV[name]
          value = (value.nil? || value.empty?) ? 0 : value.to_i
          tokens << [:number, value]
          i = j
          next
        end
        if c.match?(ARITHMETIC_OPERATOR_PATTERN)
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
      match = word.match(BRACE_EXPANSION_PATTERN)
      return [word] unless match

      prefix = match[1]
      body = match[2]
      suffix = match[3]
      return [word] unless body.include?(",")

      parts = body.split(",", -1)
      parts.flat_map { expand_braces(prefix + it + suffix) }
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
