#!/usr/bin/env ruby -w

require 'English'
require 'open3'
require 'readline'
require 'shellwords'

require './builtins'
require './colours'
require './shell_logger'
require './job'

class Shell
  attr_reader :logger, :options

  def initialize(args = ARGV)
    @builtins = Builtins.new
    @jobs_by_pid = {}
    @logger = ShellLogger.instance
    @options = parse_options(args)
    logger.verbose "Options: #{options.inspect}"
  end

  def main
    # this breaks Open3.capture3 so hold off until we fork + exec
    # trap_sigchld
    if options[:command]
      logger.verbose "Executing command: #{options[:command]}"
      print_logs
      exit process_command(options[:command])
    elsif $stdin.isatty
      add_to_history = true
      loop do
        print_logs
        line = Readline.readline(prompt(Dir.pwd), add_to_history)
        process_command(line)
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
        warn message if options[:verbose]
      else
        warn message
      end
    end
    logger.clear
  end

  def process_command(line)
    logger.verbose "Processing command: #{line.inspect}"
    exit 0 if line.nil? # EOF, ctrl-d
    return if line.empty? # no input, no-op

    args = Shellwords.split(line)
    cmd = args.shift
    logger.verbose "Words: #{cmd} #{args.inspect}"
    if @builtins.builtin?(cmd)
      logger.verbose "Executing builtin #{cmd}"
      @builtins.exec(cmd, args)
    else
      logger.verbose "Shelling out for #{cmd}"
      status = exec_command(cmd, args)
      print "#{RED}-#{status}-#{CLEAR} " unless status.zero?
    end
  end

  def exec_command(cmd, args)
    # TODO: background execution using fork + exec, streaming output
    out, err, status = Open3.capture3(cmd + ' ' + args.join(' '))
    puts out.chomp unless out.empty?
    warn err.chomp unless err.empty?
    status.exitstatus
  rescue StandardError => e
    logger.warn "#{RED}[ERROR]#{CLEAR} #{e.message}"
    1
  end
end

Shell.new(ARGV).main if $PROGRAM_NAME == __FILE__
