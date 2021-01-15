require 'thor'
require 'cabal/cli/account'
require 'cabal/cli/developer'
require 'cabal/init'


module Cabal
  class CLI
    # naive pluralizer
    def self.s(n); n != 1 ? "s" : ""; end

    class Root < Thor
      desc 'login CHAR_NAME', 'logs CHAR_NAME in if possible'
      def login(char_name)
        Cabal.init(char_name)
      end

      register CLI::Account, 'account', 'account [COMMAND]', 'account subcommands'
      # if ~/.config/cabal/developer exists, show them some secret sauce
      register CLI::Developer, 'dev', 'dev [COMMAND]', 'developer subcommands' if Cabal::XDG.exist?("developer")
    end
  end
end
