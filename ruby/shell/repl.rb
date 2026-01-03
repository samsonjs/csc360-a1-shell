begin
  require "readline"
rescue LoadError
  require "reline"
end

require "shell/builtins"
require "shell/colours"
require "shell/job_control"
require "shell/logger"
require "shell/word_expander"

module Shell
  class REPL
    include Colours

    attr_reader :builtins, :job_control, :logger, :options, :word_expander

    attr_accessor :precmd_hook

    def initialize(builtins: nil, job_control: nil, logger: nil, word_expander: nil)
      logger ||= Logger.instance
      job_control ||= JobControl.new(logger: logger)
      builtins ||= Builtins.new(job_control: job_control)
      word_expander ||= WordExpander.new

      @builtins = builtins
      @job_control = job_control
      @logger = logger
      @options = {}
      @word_expander = word_expander
    end

    def start(options: nil)
      @options = options || {}
      job_control.trap_sigchld
      add_to_history = true
      status = 0
      loop do
        precmd_hook&.call
        print "#{red(status)} " unless status.zero?
        line = Readline.readline(prompt(Dir.pwd), add_to_history)
        Readline::HISTORY.pop if line.nil? || line.strip.empty?
        status = process_command(line)
      end
    end

    def process_command(line)
      exit 0 if line.nil? # EOF, ctrl-d
      return 0 if line.strip.empty? # no input, no-op

      logger.verbose "Processing command: #{line.inspect}"
      commands = parse_line(line)
      result = nil
      commands.each do |command|
        args = word_expander.expand(command)
        program = args.shift
        logger.verbose "Parsed command: #{program} #{args.inspect}"
        if builtins.builtin?(program)
          logger.verbose "Executing builtin #{program}"
          result = builtins.exec(program, args)
        else
          logger.verbose "Shelling out for #{program}"
          result = job_control.exec_command(program, args)
        end
      end
      result
    rescue Errno => e
      warn "#{red("[ERROR]")} #{e.message}"
      -1
    end

    # Looks like this: /path/to/somewhere%
    def prompt(pwd)
      "#{blue(pwd)}#{white("%")} #{CLEAR}"
    end

    def parse_line(line)
      commands = []
      command = "".dup
      state = :unquoted
      line.each_char do |c|
        case state
        when :unquoted
          case c
          when ";"
            commands << command
            command = "".dup
          when "'"
            command << c
            state = :single_quoted
          when "\""
            command << c
            state = :double_quoted
          when "\\"
            command << c
            state = :escaped
          else
            command << c
          end

        when :single_quoted
          command << c
          state = :unquoted if c == "'"

        when :double_quoted
          case c
          when "\\"
            state = :double_quoted_escape
          else
            command << c
          end
          state = :unquoted if c == "\""

        when :double_quoted_escape
          case c
          when "\"", "\\", "$", "`"
            command << c
          else
            command << "\\" # POSIX behaviour, backslash remains
            command << c
          end
          state = :double_quoted

        when :escaped
          command << c
          state = :unquoted

        else
          raise "Unknown state #{state}"
        end
      end
      commands << command
      commands
    end
  end
end
