class Shell
  class Builtins
    attr_reader :logger

    def initialize(shell, logger = Logger.instance)
      @shell = shell
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
      @shell.exec_command(cmd, args, background: true)
    end

    def builtin_cd(args)
      Dir.chdir args.first
      0
    end

    def builtin_export(args)
      # only supports one variable and doesn't support quoting
      name, *value_parts = args.first.strip.split('=')
      if name.nil? || name.empty?
        logger.warn "#{RED}[ERROR]#{CLEAR} Invalid export command"
      else
        ENV[name] = value_parts.join('=').gsub(/\$\w+/) { |m| ENV[m[1..]] || '' }
      end
      0
    end

    def bulitin_pwd(_args)
      puts Dir.pwd
      0
    end
  end
end
