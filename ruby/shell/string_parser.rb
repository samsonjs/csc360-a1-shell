module Shell
  class StringParser
    Command = Data.define(:text, :op)
    Token = Data.define(:type, :value)

    class Scanner
      def initialize(line, index: 0)
        @line = line
        @index = index
      end

      attr_reader :index

      def tokenize_command_list
        tokens = []
        segment_start = index

        until eof?
          c = current_char
          if c == ";"
            tokens << Token.new(type: :text, value: @line[segment_start...index])
            tokens << Token.new(type: :separator, value: :always)
            advance
            segment_start = index
            next
          end

          if c == "&" && peek(1) == "&"
            tokens << Token.new(type: :text, value: @line[segment_start...index])
            tokens << Token.new(type: :separator, value: :and)
            advance(2)
            segment_start = index
            next
          end

          case c
          when "\\"
            advance_escape
          when "'"
            skip_single_quoted
          when "\""
            skip_double_quoted
          when "`"
            skip_backtick
          when "$"
            if peek(1) == "("
              if peek(2) == "("
                skip_arithmetic_substitution
              else
                skip_command_substitution
              end
            else
              advance
            end
          else
            advance
          end
        end

        tokens << Token.new(type: :text, value: @line[segment_start...index])
        tokens
      end

      # Reads the contents and end-index for a command substitution body, where
      # index points to the first character after "$(".
      def read_dollar_paren_body
        output = +""
        depth = 1

        until eof?
          c = current_char

          if c == "\\"
            output << read_escape
            next
          end

          if c == "'"
            output << read_single_quoted
            next
          end

          if c == "\""
            output << read_double_quoted
            next
          end

          if c == "`"
            output << read_backtick
            next
          end

          if c == "$" && peek(1) == "("
            if peek(2) == "("
              output << read_arithmetic_substitution
            else
              output << "$("
              advance(2)
              depth += 1
            end
            next
          end

          if c == "("
            output << c
            depth += 1
            advance
            next
          end

          if c == ")"
            depth -= 1
            if depth.zero?
              return [output, index + 1]
            end
            output << c
            advance
            next
          end

          output << c
          advance
        end

        raise ArgumentError, "Unmatched $(...)"
      end

      private

      def eof?
        index >= @line.length
      end

      def current_char
        @line[index]
      end

      def peek(offset)
        @line[index + offset]
      end

      def advance(count = 1)
        @index += count
      end

      def advance_escape
        advance
        advance unless eof?
      end

      def skip_single_quoted
        advance # opening quote
        until eof?
          if current_char == "'"
            advance
            return
          end
          advance
        end
        raise ArgumentError, "Unmatched quote"
      end

      def skip_double_quoted
        advance # opening quote
        until eof?
          c = current_char
          case c
          when "\\"
            advance_escape
          when "\""
            advance
            return
          when "`"
            skip_backtick
          when "$"
            if peek(1) == "("
              if peek(2) == "("
                skip_arithmetic_substitution
              else
                skip_command_substitution
              end
            else
              advance
            end
          else
            advance
          end
        end
        raise ArgumentError, "Unmatched quote"
      end

      def skip_backtick
        advance # opening backtick
        until eof?
          c = current_char
          case c
          when "\\"
            advance_escape
          when "`"
            advance
            return
          when "$"
            if peek(1) == "("
              if peek(2) == "("
                skip_arithmetic_substitution
              else
                skip_command_substitution
              end
            else
              advance
            end
          else
            advance
          end
        end
        raise ArgumentError, "Unmatched backtick"
      end

      def skip_command_substitution
        advance(2) # consume "$("
        depth = 1

        until eof?
          c = current_char
          case c
          when "\\"
            advance_escape
          when "'"
            skip_single_quoted
          when "\""
            skip_double_quoted
          when "`"
            skip_backtick
          when "$"
            if peek(1) == "("
              if peek(2) == "("
                skip_arithmetic_substitution
              else
                advance(2)
                depth += 1
              end
            else
              advance
            end
          when "("
            advance
            depth += 1
          when ")"
            advance
            depth -= 1
            return if depth.zero?
          else
            advance
          end
        end

        raise ArgumentError, "Unmatched $(...)"
      end

      def skip_arithmetic_substitution
        advance(3) # consume "$(("
        depth = 1

        until eof?
          c = current_char
          case c
          when "\\"
            advance_escape
          when "'"
            skip_single_quoted
          when "\""
            skip_double_quoted
          when "`"
            skip_backtick
          when "$"
            if peek(1) == "("
              if peek(2) == "("
                advance(3)
                depth += 1
              else
                skip_command_substitution
              end
            else
              advance
            end
          when ")"
            if peek(1) == ")"
              advance(2)
              depth -= 1
              return if depth.zero?
            else
              advance
            end
          else
            advance
          end
        end

        raise ArgumentError, "Unmatched $((...))"
      end

      def read_escape
        start = index
        advance_escape
        @line[start...index]
      end

      def read_single_quoted
        start = index
        skip_single_quoted
        @line[start...index]
      end

      def read_double_quoted
        start = index
        skip_double_quoted
        @line[start...index]
      end

      def read_backtick
        start = index
        skip_backtick
        @line[start...index]
      end

      def read_arithmetic_substitution
        start = index
        skip_arithmetic_substitution
        @line[start...index]
      end
    end

    class << self
      def split_commands(line)
        commands = []
        next_op = :always
        tokens = Scanner.new(line).tokenize_command_list

        tokens.each do |token|
          case token
          in Token[type: :text, value:]
            if next_op == :and && value.strip.empty?
              raise ArgumentError, "syntax error: expected command after `&&`"
            end
            commands << Command.new(text: value, op: next_op)
            next_op = :always
          in Token[type: :separator, value: :and]
            if commands.empty? || commands.last.text.strip.empty?
              raise ArgumentError, "syntax error near unexpected token `&&`"
            end
            next_op = :and
          in Token[type: :separator, value: :always]
            next_op = :always
          else
            raise ArgumentError, "Unknown token type: #{token.type}"
          end
        end

        commands
      end

      def read_dollar_paren(line, start_index) = Scanner.new(line, index: start_index).read_dollar_paren_body
    end
  end
end
