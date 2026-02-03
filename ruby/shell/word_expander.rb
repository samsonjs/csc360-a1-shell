require "shellwords"
require "open3"

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
        .map do |word|
          expand_variables(word)
            .tr(ESCAPED_DOLLAR, "$")
            .tr(ESCAPED_BACKTICK, "`")
          # TODO: expand globs
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
      state = :unquoted
      while i < line.length
        c = line[i]
        case state
        when :unquoted
          case c
          when "'"
            output << c
            state = :single_quoted
            i += 1
          when "\""
            output << c
            state = :double_quoted
            i += 1
          when "`"
            cmd, i = read_backtick(line, i + 1)
            output << run_command_substitution(cmd)
          when "$"
            if line[i + 1] == "("
              cmd, i = read_dollar_paren(line, i + 2)
              output << run_command_substitution(cmd)
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
                output << c
                i += 1
              end
            else
              output << c
              i += 1
            end
          else
            output << c
            i += 1
          end

        when :single_quoted
          output << c
          state = :unquoted if c == "'"
          i += 1

        when :double_quoted
          case c
          when "\""
            output << c
            state = :unquoted
            i += 1
          when "\\"
            if i + 1 < line.length
              escaped = line[i + 1]
              if escaped == "$" || escaped == "`" || escaped == "\\" || escaped == "\""
                output << escaped_replacement(escaped)
              else
                output << "\\"
                output << escaped
              end
              i += 2
            else
              output << c
              i += 1
            end
          when "`"
            cmd, i = read_backtick(line, i + 1)
            output << run_command_substitution(cmd)
          when "$"
            if line[i + 1] == "("
              cmd, i = read_dollar_paren(line, i + 2)
              output << run_command_substitution(cmd)
            else
              output << c
              i += 1
            end
          else
            output << c
            i += 1
          end
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
      output = +""
      i = start_index
      depth = 1
      state = :unquoted
      while i < line.length
        c = line[i]
        case state
        when :unquoted
          case c
          when "("
            depth += 1
          when ")"
            depth -= 1
            return [output, i + 1] if depth.zero?
          when "'"
            state = :single_quoted
          when "\""
            state = :double_quoted
          end
          output << c
        when :single_quoted
          output << c
          state = :unquoted if c == "'"
        when :double_quoted
          output << c
          state = :unquoted if c == "\""
        end
        i += 1
      end
      raise ArgumentError, "Unmatched $(...)"
    end

    def run_command_substitution(command)
      stdout, status = Open3.capture2("/bin/sh", "-c", command)
      raise Errno::ENOENT, command unless status.success?
      stdout = stdout.sub(/\n+\z/, "")
      stdout.tr("\n", " ")
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
