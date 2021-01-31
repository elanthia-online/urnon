require 'urnon/eaccess'

module Urnon
  class CLI
    class Account < Thor
      desc 'list', 'list all known accounts'
      def list()
        Urnon::XDG.accounts { |accounts|
          names = accounts.keys
          puts "urnon knows about %s account#{CLI.s(names.size)}\n- %s" % [names.size, names.join("\n- ")]
        }
      end

      desc 'add ACCOUNT PASSWORD', 'add ACCOUNT to local storage for quick logins'
      def add(account, password)
        EAccess.auth(account: account, password: password) {|rows|
          characters = rows.map(&:last)
          Urnon::XDG.accounts { |accounts|
            accounts[account] = {
              "password" => password,
              "characters" => characters,
            }
          }
          puts "discovered %s character#{CLI.s(characters.size)} for account %s\n- %s" % [
            characters.size,
            account,
            characters.join("\n- ")
            ]
        }
      end

      desc 'forget ACCOUNT', 'forget everything know about an account'
      def forget(account)
        Urnon::XDG.accounts { |accounts|
          forgettable, _details = accounts.find {|key, val|
            key.downcase.eql?(account.downcase)
          }
          return puts 'nothing was known about %s' % account if forgettable.nil?
          accounts.delete(forgettable) if forgettable
          puts 'forgot about %s' % forgettable
        }
      end
    end
  end
end
