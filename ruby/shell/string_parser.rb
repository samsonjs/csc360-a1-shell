require "shell/quote_cursor"

module Shell
  class StringParser
    class << self
      def split_commands(line)
        commands = []
        command = +""
        cursor = QuoteCursor.new
        next_op = :always
        i = 0

        while i < line.length
          c = line[i]
          if cursor.unquoted?
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
            end
          end

          segment, i = cursor.consume(line, i)
          command << segment
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
        cursor = QuoteCursor.new

        while i < line.length
          c = line[i]

          if cursor.unquoted?
            case c
            when "("
              depth += 1
            when ")"
              depth -= 1
              return [output, i + 1] if depth.zero?
            end
          end

          segment, i = cursor.consume(line, i)
          output << segment
        end

        raise ArgumentError, "Unmatched $(...)"
      end
    end
  end
end
