require './colours'
require './job'

class Shell
  class JobControl
    include Colours

    attr_reader :logger

    def initialize(logger = Logger.instance)
      @jobs_by_pid = {}
      @logger = logger
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

    def exec_command(cmd, args, background: false)
      unless (path = resolve_executable(cmd))
        warn "#{RED}[ERROR]#{CLEAR} command not found: #{cmd}"
        return -2
      end

      pid = fork { exec([path, cmd], *args) }
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
end
