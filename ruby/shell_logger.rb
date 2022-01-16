# Queues up messages to be printed out when readline is waiting for input, to prevent
# mixing shell output with command output.
class ShellLogger
  Log = Struct.new(:level, :message)

  attr_reader :logs

  def initialize
    clear
  end

  def log(message)
    @logs << Log.new(:info, message)
  end
  alias info log

  def warn(message)
    @logs << Log.new(:warning, message)
  end

  def verbose(message)
    @logs << Log.new(:verbose, message)
  end

  def clear
    @logs = []
    nil
  end
end
