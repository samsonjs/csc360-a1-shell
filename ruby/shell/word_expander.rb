require "shellwords"

module Shell
  class WordExpander
    ENV_VAR_REGEX = /\$(?:\{([^}]+)\}|(\w+)\b)/

    # Splits the given line into multiple words, performing the following transformations:
    #
    # - Splits into words taking quoting and backslash escaping into account
    # - Expands environment variables using $NAME and ${NAME} syntax
    # - Tilde expansion, which means that ~ is expanded to $HOME
    # - Glob expansion on files and directories
    def expand(line)
      shellsplit(line)
        .map do |word|
          word
            .gsub(ENV_VAR_REGEX) do
              name = Regexp.last_match(2) || Regexp.last_match(1)
              ENV.fetch(name)
            end
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
      line.scan(/\G\s*(?>([^\0\s\\'"]+)|'([^\0']*)'|"((?:[^\0"\\]|\\[^\0])*)"|(\\[^\0]?)|(\S))(\s|\z)?/m) do
        |word, sq, dq, esc, garbage, sep|
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
          field.sub!(/^~/, Dir.home)
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
  end
end
