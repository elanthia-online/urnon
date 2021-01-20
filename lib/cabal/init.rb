require 'benchmark'
require 'time'
require 'socket'
require 'stringio'
require 'zlib'
require 'resolv'
require 'digest/md5'
require 'openssl'
require 'fileutils'
require("cabal/util/util")
require("cabal/lich/lich")
## primative extensions to String, etc
require("cabal/lich/ext")
## Lich stuff
require("cabal/lich/string-proc")
require("cabal/lich/synchronized-socket")
require("cabal/lich/limited-array")
require("cabal/lich/upstream-hook")
require("cabal/lich/downstream-hook")
require("cabal/lich/setting")
require("cabal/lich/game-settings")
require("cabal/lich/vars")
require("cabal/lich/watchfor")
require("cabal/script/script")
require("cabal/script/exec-script")
require("cabal/lich/map")
require("cabal/lich/room")
require("cabal/lich/settings")
require("cabal/lich/char-settings")
require("cabal/lich/format")
require("cabal/lich/shared-buffer")
require("cabal/lich/spell-ranks")
require("cabal/lich/spell")
require("cabal/eaccess")
require("cabal/lich/decoders")
require("cabal/lich/settings")
require("cabal/lich/spell-song")
require("cabal/lich/duplicate-defs")
require("cabal/lich/gtk3")

# - Migrated Lich Utils
require("cabal/session") # was Game
# - lich script inter-dependency manager
require("cabal/package")
require("cabal/lich/client")
require("cabal/xdg")
require("cabal/util/opts")
require("cabal/autostart")
require 'cabal/constants'
# hacky closure for now
module Cabal
  def self.setup()
    [TEMP_DIR, DATA_DIR, SCRIPT_DIR, MAP_DIR, LOG_DIR, BACKUP_DIR].each do |dir|
      FileUtils.mkdir_p(dir)
    end
    Lich.init_db
  end

  def self.init(character)
    Cabal.setup

    (account, account_info) = Cabal::XDG.account_for(character)

    account = account || ENV["ACCOUNT"]

    fail Exception, "ACCOUNT is required" if account.nil?

    argv = OpenStruct.new(
      {  account: account,
      game_code: (ENV["GAME"] || "GS3"),
      character: character}.merge(account_info))

    # use env variables so they are not in logs
    ENV["PASSWORD"] or argv.password or fail Exception, "PASSWORD is required"

    login_info = EAccess.auth(
      account:   ENV["ACCOUNT"]  || argv.account,
      password:  ENV["PASSWORD"] || argv.password,
      game_code: argv.game_code,
      character: argv.character)
    #
    # connect to GSIV only for right now
    #
    session = Session.open(
      login_info["gamehost"],
      login_info["gameport"],
      argv.port)
    session.init(login_info["key"])
    Thread.current.priority = -10
    Gtk.main
    Script.list.each { |script| script.kill if script.session.eql?(session) }
    session.client_thread.kill rescue nil
    session.close
    wait_until {session.closed?}
  end
end
