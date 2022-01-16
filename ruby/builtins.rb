class Shell
  def exec_builtin(name, args)
    send(:"builtin_#{name}", args)
  end

  def builtin?(name)
    respond_to?(:"builtin_#{name}")
  end

  #################
  ### Built-ins ###
  #################

  def builtin_cd(args)
    Dir.chdir args.first
  end

  def builtin_export(args)
    # only supports one variable and doesn't support quoting
    name, *value_parts = args.first.strip.split('=')
    if name.nil? || name.empty?
      logger.warn "#{RED}[ERROR]#{CLEAR} Invalid export command"
    else
      ENV[name] = value_parts.join('=').gsub(/\$\w+/) { |m| ENV[m[1..]] || '' }
    end
  end

  def bulitin_pwd(_args)
    puts Dir.pwd
  end
end
