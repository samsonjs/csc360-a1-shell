module Shell
  class StringParser
    class << self
      def split_commands(line)
        commands = []
        command = +""
        state = :unquoted
        next_op = :always
        i = 0

        while i < line.length
          c = line[i]
          case state
          when :unquoted
            case c
            when ";"
              commands << {command: command, op: next_op}
              command = +""
              next_op = :always
              i += 1
              next
            when "&"
              if line[i + 1] == "&"
                if command.strip.empty?
                  raise ArgumentError, "syntax error near unexpected token `&&`"
                end
                commands << {command: command, op: next_op}
                command = +""
                next_op = :and
                i += 2
                next
              end
            when "'"
              state = :single_quoted
            when "\""
              state = :double_quoted
            when "\\"
              state = :escaped
            end
            command << c

          when :single_quoted
            command << c
            state = :unquoted if c == "'"

          when :double_quoted
            command << c
            if c == "\\"
              state = :double_quoted_escape
            elsif c == "\""
              state = :unquoted
            end

          when :double_quoted_escape
            command << c
            state = :double_quoted

          when :escaped
            command << c
            state = :unquoted

          else
            raise "Unknown state #{state}"
          end

          i += 1
        end

        if next_op == :and && command.strip.empty?
          raise ArgumentError, "syntax error: expected command after `&&`"
        end

        commands << {command: command, op: next_op}
        commands
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
              output << c
            when ")"
              depth -= 1
              return [output, i + 1] if depth.zero?
              output << c
            when "'"
              output << c
              state = :single_quoted
            when "\""
              output << c
              state = :double_quoted
            when "\\"
              output << c
              if i + 1 < line.length
                output << line[i + 1]
                i += 1
              end
            else
              output << c
            end

          when :single_quoted
            output << c
            state = :unquoted if c == "'"

          when :double_quoted
            if c == "\\"
              output << c
              if i + 1 < line.length
                output << line[i + 1]
                i += 1
              end
            else
              output << c
              state = :unquoted if c == "\""
            end

          else
            raise "Unknown state #{state}"
          end

          i += 1
        end

        raise ArgumentError, "Unmatched $(...)"
      end
    end
  end
end
