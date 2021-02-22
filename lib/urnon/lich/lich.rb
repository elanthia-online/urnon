require 'sequel'
require 'logger'

module Lich
  @@lich_db = nil

  def self._db()
    Sequel.sqlite(
      File.join(DATA_DIR, 'lich.db3'), loggers: [Logger.new($stdout)])
  end

  def Lich.db
    @@lich_db ||= _db()
  end

  def Lich.init_db
    Lich.db.execute("CREATE TABLE IF NOT EXISTS script_setting (script TEXT NOT NULL, name TEXT NOT NULL, value BLOB, PRIMARY KEY(script, name));")
    Lich.db.execute("CREATE TABLE IF NOT EXISTS script_auto_settings (script TEXT NOT NULL, scope TEXT, hash BLOB, PRIMARY KEY(script, scope));")
    Lich.db.execute("CREATE TABLE IF NOT EXISTS lich_settings (name TEXT NOT NULL, value TEXT, PRIMARY KEY(name));")
    Lich.db.execute("CREATE TABLE IF NOT EXISTS uservars (scope TEXT NOT NULL, hash BLOB, PRIMARY KEY(scope));")
    Lich.db.execute("CREATE TABLE IF NOT EXISTS enable_inventory_boxes (player_id INTEGER NOT NULL, PRIMARY KEY(player_id));")
  end

  def Lich.log(msg)
    begin
      $stderr.puts "#{Time.now.strftime("%Y-%m-%d %H:%M:%S")}: #{msg}"
    rescue => exception
      respond exception.message
    end
  end


  def Lich.inventory_boxes(player_id)
    self.db[:enable_inventory_boxes].first(player_id: player_id.to_i)
  end

  def Lich.set_inventory_boxes(player_id, enabled)
     if enabled
        begin
           Lich.db.execute('INSERT OR REPLACE INTO enable_inventory_boxes values(?);', player_id.to_i)
        rescue SQLite3::BusyException
           sleep 0.1
           retry
        end
     else
        begin
           Lich.db.execute('DELETE FROM enable_inventory_boxes where player_id=?;', player_id.to_i)
        rescue SQLite3::BusyException
           sleep 0.1
           retry
        end
     end
     nil
  end
end
