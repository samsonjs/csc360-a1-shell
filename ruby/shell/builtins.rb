require 'shell/job_control'
require 'shell/logger'

module Shell
  class Builtins
    attr_reader :job_control, :logger

    def initialize(job_control: nil, logger: nil)
      logger ||= Logger.instance
      @job_control = job_control || JobControl.new(logger: logger)
      @logger = logger
    end

    def exec(name, args)
      send(:"builtin_#{name}", args)
    end

    def builtin?(name)
      respond_to?(:"builtin_#{name}")
    end

    #################
    ### Built-ins ###
    #################

    def builtin_bg(args)
      cmd = args.shift
      job_control.exec_command(cmd, args, background: true)
    end

    def builtin_bglist(_args)
      jobs = job_control.list
      puts unless jobs.empty?
      jobs.each do |job|
        puts job_control.format_job(job)
      end
      plural = jobs.count == 1 ? '' : 's'
      puts "#{jobs.count} background job#{plural}"
      0
    end

    def builtin_bgkill(args)
      if args.count != 1
        logger.warn 'Usage: bgkill <job>'
        return -1
      end

      job_id = args.shift.to_i
      job_control.kill(job_id)
      0
    end

    def builtin_cd(args)
      Dir.chdir args.first
      0
    end

    def builtin_export(args)
      # only supports one variable and doesn't support quoting
      name, *value_parts = args.first.strip.split('=')
      if name.nil? || name.empty?
        logger.warn "#{red('[ERROR]')} Invalid export command"
      else
        ENV[name] = value_parts.join('=').gsub(/\$\w+/) { |m| ENV[m[1..]] || '' }
      end
      0
    end

    def builtin_pwd(_args)
      puts Dir.pwd
      0
    end

    def builtin_clear(_args)
      print "\033[2J"
      0
    end
  end
end
