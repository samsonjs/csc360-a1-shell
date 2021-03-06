module Shell
  module Colours
    # These colours should be safe on dark and light backgrounds.
    BLUE = "\033[1;34m".freeze
    GREEN = "\033[1;32m".freeze
    YELLOW = "\033[1;33m".freeze
    RED = "\033[1;31m".freeze
    WHITE = "\033[1;37m".freeze
    CLEAR = "\033[0;m".freeze

    def self.included(mod)
      Colours.constants.each do |sym|
        next if sym == :CLEAR
        mod.define_method(sym.to_s.downcase) do |*text|
          "#{Colours.const_get(sym)}#{text.join}#{CLEAR}"
        end
      end
    end
  end
end
