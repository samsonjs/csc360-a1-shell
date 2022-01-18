#!/usr/bin/env ruby -w

require 'English'
require 'readline'
require 'wordexp'

require './builtins'
require './colours'
require './job_control'
require './logger'

# TODO: change to module after extracting all or most of the code
class Shell
  include Colours

  attr_reader :builtins, :job_control, :logger, :options

  def initialize(args: ARGV, builtins: nil, job_control: nil, logger: nil)
    logger ||= Logger.instance
    job_control ||= JobControl.new
    builtins ||= Builtins.new(job_control)
    @builtins = builtins
    @job_control = job_control
    @logger = logger
    @options = parse_options(args)
    logger.verbose "Options: #{options.inspect}"
  end

  def main
    if options[:command]
      logger.verbose "Executing command: #{options[:command]}"
      print_logs
      exit process_command(options[:command])
    end
    repl if $stdin.isatty
  end

  def repl
    @job_control.trap_sigchld
    add_to_history = true
    status = 0
    loop do
      print_logs
      print "#{RED}#{status}#{CLEAR} " unless status.zero?
      line = Readline.readline(prompt(Dir.pwd), add_to_history)
      Readline::HISTORY.pop if line.nil? || line.strip.empty?
      status = process_command(line)
    end
  end

  # Looks like this: /path/to/somewhere%
  def prompt(pwd)
    "#{BLUE}#{pwd}#{WHITE}% #{CLEAR}"
  end

  def parse_options(args)
    options = {
      verbose: false,
    }
    while (arg = args.shift)
      case arg
      when '-c'
        options[:command] = args.shift
      when '-v', '--verbose'
        options[:verbose] = true
      else
        logger.warn "#{RED}[ERROR]#{CLEAR} Unknown argument: #{arg}"
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

  def process_command(line)
    exit 0 if line.nil? # EOF, ctrl-d
    return 0 if line.strip.empty? # no input, no-op

    logger.verbose "Processing command: #{line.inspect}"
    args = Wordexp.expand(line)
    cmd = args.shift
    logger.verbose "Parsed command: #{cmd} #{args.inspect}"
    if @builtins.builtin?(cmd)
      logger.verbose "Executing builtin #{cmd}"
      @builtins.exec(cmd, args)
    else
      logger.verbose "Shelling out for #{cmd}"
      @job_control.exec_command(cmd, args)
    end
  rescue Errno => e
    warn "#{RED}[ERROR]#{CLEAR} #{e.message}"
    -1
  end
end

Shell.new(args: ARGV).main if $PROGRAM_NAME == __FILE__
