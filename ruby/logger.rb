require './colours'

class Shell
  # Queues up messages to be printed out when readline is waiting for input, to prevent
  # mixing shell output with command output.
  class Logger
    include Colours

    Log = Struct.new(:level, :message)

    attr_reader :logs

    def self.instance
      @instance ||= new
    end

    def initialize
      clear
    end

    def log(message)
      @logs << Log.new(:info, "#{white('[INFO]')} #{message}")
    end
    alias info log

    def warn(message)
      @logs << Log.new(:warning, "#{yellow('[WARN]')} #{message}")
    end

    def error(message)
      @logs << Log.new(:error, "#{red('[ERROR]')} #{message}")
    end

    def verbose(message)
      @logs << Log.new(:verbose, "[VERBOSE] #{message}")
    end

    def clear
      @logs = []
      nil
    end
  end
end
