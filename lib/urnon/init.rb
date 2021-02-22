require 'benchmark'
require 'time'
require 'socket'
require 'stringio'
require 'zlib'
require 'resolv'
require 'digest/md5'
require 'openssl'
require 'fileutils'
require 'urnon/util/util'
require 'urnon/lich/lich'
## primative extensions to String, etc
require 'urnon/ext/string'
require 'urnon/ext/nilclass'
require 'urnon/ext/numeric'
## scripting utils
require 'urnon/script/script'
require 'urnon/script/exec-script'
## all the various types of Settings
require 'urnon/settings/settings'
require 'urnon/settings/char-settings'
require 'urnon/settings/game-settings'
require 'urnon/settings/vars'
require 'urnon/settings/user-vars'
## Lich stuff
require 'urnon/lich/string-proc'
require 'urnon/lich/watchfor'
require 'urnon/lich/decoders'

# map
require 'urnon/map/room'

require 'urnon/util/synchronized-socket'
require 'urnon/util/limited-array'
require 'urnon/util/format'
require 'urnon/util/shared-buffer'

# - Migrated Lich Utils
require 'urnon/session' # was Game
require 'urnon/eaccess' # ssl gateway support
# - lich script inter-dependency manager
require 'urnon/package'
require 'urnon/lich/client'
require 'urnon/xdg'
require 'urnon/util/opts'
require 'urnon/autostart'
require 'urnon/constants'
# hacky closure for now
module Urnon
  def self.setup()
    [TEMP_DIR, DATA_DIR, SCRIPT_DIR, MAP_DIR, LOG_DIR, BACKUP_DIR].each do |dir|
      FileUtils.mkdir_p(dir)
    end
    Lich.init_db
  end

  def self.init(character)
    Urnon.setup
    (account, account_info) = Urnon::XDG.account_for(character)

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

    pp "login=%s" % argv.character


    Thread.new {
      #
      # connect to GSIV only for right now
      #
      session = Session.open(
        login_info["gamehost"],
        login_info["gameport"],
        argv.port)

      session.init(login_info["key"])
      Thread.current.priority = -5
      sleep 0.1 until session.closed?
      Script.list.each { |script| script.kill if script.session.eql?(session) }
      session.close
    }
  end
end
