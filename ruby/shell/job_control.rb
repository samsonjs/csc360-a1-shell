require 'English'

require 'shell/colours'
require 'shell/job'
require 'shell/logger'

module Shell
  class JobControl
    include Colours

    attr_reader :logger

    def initialize(logger: nil)
      @jobs_by_pid = {}
      @logger = logger || Logger.instance
    end

    def exec_command(cmd, args, background: false)
      unless (path = resolve_executable(cmd))
        warn "#{red('[ERROR]')} command not found: #{cmd}"
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
          logger.verbose "#{yellow(e.message)} but child was just forked 🧐"
          0
        end
      end
    rescue StandardError => e
      warn "#{red('[ERROR]')} #{e.message} #{e.inspect}"
      -5
    end

    def kill(job_id)
      job = @jobs_by_pid.values.detect { |j| j.id == job_id }
      if job.nil?
        logger.warn "No job found with ID #{job_id}"
        return
      end

      Process.kill('TERM', job.pid)
    rescue Errno::ESRCH
      logger.warn "No such proccess: #{job.pid}"
    end

    def list
      @jobs_by_pid.values.sort_by(&:id)
    end

    def format_job(job)
      args = job.args.join(' ')
      "#{yellow(job.id)}: #{white('(pid ', job.pid, ')')} #{green(job.cmd)} #{args}"
    end

    def trap_sigchld
      # handler for SIGCHLD when a child's state changes
      Signal.trap('CHLD') do |_signo|
        pid = Process.waitpid(-1, Process::WNOHANG)
        if pid.nil?
          # no-op
        elsif (job = @jobs_by_pid[pid])
          @jobs_by_pid.delete(pid)
          time = Time.now.strftime('%T')
          job_text = yellow('job ', job.id, ' exited')
          args = job.args.join(' ')
          puts "\n[#{time}] #{job_text} #{white('(pid ', job.pid, ')')}: #{green(job.cmd)} #{args}"
        else
          warn "\n#{yellow('[WARN]')} No job found for child with PID #{pid}"
        end
        Readline.refresh_line
      end
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
