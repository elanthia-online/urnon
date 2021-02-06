require 'thor'
require 'urnon/cli/account'
require 'urnon/cli/developer'
require 'urnon/init'

module Urnon
  class CLI
    # naive pluralizer
    def self.s(n); n != 1 ? "s" : ""; end

    class Root < Thor

      desc 'login', 'login a set of characters'
      method_option :chars,
                    type: :array,
                    aliases: "-c"

      def login()
        Thread.main.priority = -10
        session_threads = options.chars.map { |name| Urnon.init(name) }
        sleep 0.1 while session_threads.any?(&:alive?)
      end

      register CLI::Account, 'account', 'account [COMMAND]', 'account subcommands'
      # if ~/.config/urnon/developer exists, show them some secret sauce
      register CLI::Developer, 'dev', 'dev [COMMAND]', 'developer subcommands' if Urnon::XDG.exist?("developer")
    end
  end
end
