require 'thor'
require 'cabal/cli/account'
require 'cabal/cli/developer'
require 'cabal/init'

module Cabal
  class CLI
    # naive pluralizer
    def self.s(n); n != 1 ? "s" : ""; end

    class Root < Thor

      desc 'login', 'login a set of characters'
      method_option :chars,
                    type: :array,
                    aliases: "-c"

      def login()
        options.chars.map { |name| Cabal.init(name) }
      end

      register CLI::Account, 'account', 'account [COMMAND]', 'account subcommands'
      # if ~/.config/cabal/developer exists, show them some secret sauce
      register CLI::Developer, 'dev', 'dev [COMMAND]', 'developer subcommands' if Cabal::XDG.exist?("developer")
    end
  end
end
