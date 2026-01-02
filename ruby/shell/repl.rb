begin
  require "readline"
rescue LoadError
  require "reline"
end
require "wordexp"

require "shell/builtins"
require "shell/colours"
require "shell/job_control"
require "shell/logger"

module Shell
  class REPL
    include Colours

    attr_reader :builtins, :job_control, :logger, :options

    attr_accessor :precmd_hook

    def initialize(builtins: nil, job_control: nil, logger: nil)
      logger ||= Logger.instance
      job_control ||= JobControl.new(logger: logger)
      builtins ||= Builtins.new(job_control: job_control)

      @builtins = builtins
      @job_control = job_control
      @logger = logger
      @options = {}
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
      args = Wordexp.expand(line)
      cmd = args.shift
      logger.verbose "Parsed command: #{cmd} #{args.inspect}"
      if builtins.builtin?(cmd)
        logger.verbose "Executing builtin #{cmd}"
        builtins.exec(cmd, args)
      else
        logger.verbose "Shelling out for #{cmd}"
        job_control.exec_command(cmd, args)
      end
    rescue Errno => e
      warn "#{red("[ERROR]")} #{e.message}"
      -1
    end

    # Looks like this: /path/to/somewhere%
    def prompt(pwd)
      "#{blue(pwd)}#{white("%")} #{CLEAR}"
    end
  end
end
