module Shell
  # Shared quote/escape state machine for parsers that walk shell-like strings.
  class QuoteCursor
    attr_reader :state

    def initialize(state: :unquoted)
      @state = state
    end

    def unquoted?
      state == :unquoted
    end

    # Consumes one logical unit from line[index], which may be one character
    # or an escape pair (e.g., \" or \\$), and updates internal quote state.
    # Returns [segment, next_index].
    def consume(line, index)
      c = line[index]

      case state
      when :unquoted
        consume_unquoted(line, index, c)
      when :single_quoted
        consume_single_quoted(index, c)
      when :double_quoted
        consume_double_quoted(line, index, c)
      else
        raise "Unknown state #{state}"
      end
    end

    private

    def consume_unquoted(line, index, c)
      case c
      when "'"
        @state = :single_quoted
      when "\""
        @state = :double_quoted
      when "\\"
        if index + 1 < line.length
          return [line[index, 2], index + 2]
        end
      end
      [c, index + 1]
    end

    def consume_single_quoted(index, c)
      @state = :unquoted if c == "'"
      [c, index + 1]
    end

    def consume_double_quoted(line, index, c)
      if c == "\\"
        if index + 1 < line.length
          return [line[index, 2], index + 2]
        end
      elsif c == "\""
        @state = :unquoted
      end
      [c, index + 1]
    end
  end
end
