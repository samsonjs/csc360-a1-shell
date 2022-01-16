#!/usr/bin/env ruby -w

require 'English'
require 'open3'
require 'readline'

require './builtins'
require './colours'
require './shell_logger'
require './job'

class Shell
  attr_reader :logger, :options

  def initialize(args)
    @logger = ShellLogger.new
    @options = parse_options(args)
    @jobs_by_pid = {}
    @builtins = Builtins.new(@logger)
    logger.verbose "options: #{options.inspect}"
  end

  def main
    # this breaks Open3.capture3 so hold off until we fork + exec
    # trap_sigchld
    if options[:command]
      logger.verbose "Executing command: #{options[:command]}"
      print_logs
      exit exec_command(options[:command])
    elsif $stdin.isatty
      add_to_history = true
      loop do
        print_logs
        cmd = Readline.readline(prompt(Dir.pwd), add_to_history)
        process_command(cmd)
      end
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

  def trap_sigchld
    # handler for SIGCHLD when a child's state changes
    Signal.trap('CHLD') do |signo|
      logger.info "SIGCHLD #{signo}"
      pid = Process.waitpid(-1, Process::WNOHANG)
      if (job = @jobs_by_pid[pid])
        logger.info "#{YELLOW}#{job.id}#{CLEAR}: #{WHITE}(pid #{pid})#{CLEAR} #{job.cmd}"
      else
        logger.warn "No job found for child with PID #{pid}"
      end
    end
  end

  def print_logs
    logger.logs.each do |log|
      message = "#{log.message}#{CLEAR}"
      case log.level
      when :verbose
        puts message if options[:verbose]
      when :warning
        warn message
      else
        puts message
      end
    end
    logger.clear
  end

  def process_command(cmd)
    logger.verbose "Processing command: #{cmd.inspect}"
    exit 0 if cmd.nil? # EOF, ctrl-d
    return if cmd.empty? # no input, no-op

    # TODO: proper word splitting, pass arrays to built-ins
    args = cmd.split
    argv0 = args.first
    logger.verbose "\"Words\": #{args.inspect}"
    if @builtins.builtin?(argv0)
      logger.verbose "Executing builtin #{argv0}"
      args.shift
      @builtins.exec(argv0, args)
    else
      logger.verbose "Shelling out for #{argv0}"
      status = exec_command(cmd)
      print "#{RED}-#{status}-#{CLEAR} " unless status.zero?
    end
  end

  def exec_command(cmd)
    # TODO: background execution using fork + exec, streaming output
    out, err, status = Open3.capture3(cmd)
    puts out.chomp unless out.empty?
    warn err.chomp unless err.empty?
    status.exitstatus
  rescue StandardError => e
    logger.warn "#{RED}[ERROR]#{CLEAR} #{e.message}"
    1
  end
end

Shell.new(ARGV).main if $PROGRAM_NAME == __FILE__
