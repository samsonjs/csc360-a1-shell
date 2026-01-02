require "shell/colours"
require "shell/logger"
require "shell/repl"

module Shell
  class CLI
    include Colours

    attr_reader :logger, :options, :repl

    def initialize(logger: nil, repl: nil)
      @logger = logger || Logger.instance
      @options = {}
      @repl = repl || REPL.new(logger: @logger)
      @repl.precmd_hook = -> { print_logs }
    end

    def run(args: nil)
      @options = parse_options(args || ARGV)
      logger.verbose "Options: #{options.inspect}"
      if options[:command]
        logger.verbose "Executing command: #{options[:command]}"
        print_logs
        exit repl.process_command(options[:command])
      elsif $stdin.isatty
        repl.start(options: options)
      end
    end

    def parse_options(args)
      options = {
        verbose: false
      }
      while (arg = args.shift)
        case arg
        when "-c"
          options[:command] = args.shift
          if options[:command].nil?
            warn "ERROR: expected string after -c"
            exit 1
          end
        when "-v", "--verbose"
          options[:verbose] = true
        else
          logger.warn "#{red("[ERROR]")} Unknown argument: #{arg}"
          exit 1
        end
      end
      options
    end

    def print_logs
      logger.logs.each do |log|
        message = "#{log.message}#{CLEAR}"
        case log.level
        when :verbose
          warn message if options[:verbose]
        else
          warn message
        end
      end
      logger.clear
    end
  end
end
