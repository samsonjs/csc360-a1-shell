#!/usr/bin/env ruby -w

require 'English'
require 'open3'
require 'readline'
require 'wordexp'

require './builtins'
require './colours'
require './logger'
require './job'

class Shell
  attr_reader :logger, :options

  def initialize(args = ARGV)
    @builtins = Builtins.new(self)
    @jobs_by_pid = {}
    @logger = Logger.instance
    @options = parse_options(args)
    logger.verbose "Options: #{options.inspect}"
  end

  def main
    trap_sigchld
    if options[:command]
      logger.verbose "Executing command: #{options[:command]}"
      print_logs
      exit process_command(options[:command])
    elsif $stdin.isatty
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
    Signal.trap('CHLD') do |_signo|
      pid = Process.waitpid(-1, Process::WNOHANG)
      if pid.nil?
        # no-op
      elsif (job = @jobs_by_pid[pid])
        puts "\n#{YELLOW}#{job.id}#{CLEAR}: " \
             "#{WHITE}(pid #{pid})#{CLEAR} "  \
             "#{GREEN}#{job.cmd}#{CLEAR} "    \
             "#{job.args.inspect}"
      else
        warn "\n#{YELLOW}[WARN]#{CLEAR} No job found for child with PID #{pid}"
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
      exec_command(cmd, args)
    end
  rescue Errno => e
    warn "#{RED}[ERROR]#{CLEAR} #{e.message}"
    -1
  end

  def exec_command(cmd, args, background: false)
    unless (path = resolve_executable(cmd))
      warn "#{RED}[ERROR]#{CLEAR} command not found: #{cmd}"
      return -2
    end

    pid = fork
    if pid
      # parent
      if background
        job = Job.new(next_job_id, pid, cmd, args)
        @jobs_by_pid[pid] = job
        puts "Background job #{job.id} (pid #{pid})"
        Process.waitpid(pid, Process::WNOHANG)
        0
      else
        begin
          Process.waitpid(pid)
          $CHILD_STATUS.exitstatus
        rescue Errno::ECHILD => e
          # FIXME: why does this happen? doesn't seem to be a real problem
          logger.verbose "#{YELLOW}#{e.message}#{CLEAR} but child was just forked 🧐"
          0
        end
      end
    else
      # child
      exec([path, cmd], *args)
      # if we make it here then exec failed
      -4
    end
  rescue StandardError => e
    warn "#{RED}[ERROR]#{CLEAR} #{e.message} #{e.inspect}"
    -5
  end

  # Return absolute and relative paths directly, or searches PATH for a
  # matching executable with the given filename and returns its path.
  # Returns nil when no such command was found.
  def resolve_executable(path_or_filename)
    # process absolute and relative paths directly
    return path_or_filename if path_or_filename['/'] && \
                               File.executable?(path_or_filename)

    filename = path_or_filename
    ENV['PATH'].split(':').each do |dir|
      path = File.join(dir, filename)
      next unless File.exist?(path)
      return path if File.executable?(path)
      logger.warn "Found #{path} but it's not executable"
    end
    nil
  end

  def next_job_id
    (@jobs_by_pid.values.map(&:id).max || 0) + 1
  end
end

Shell.new(ARGV).main if $PROGRAM_NAME == __FILE__
