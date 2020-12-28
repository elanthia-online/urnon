module Lich
  @@lich_db = nil

  def Lich.db
    @@lich_db ||= SQLite3::Database.new("#{DATA_DIR}/lich.db3")
  end

  def Lich.init_db
    begin
      Lich.db.execute("CREATE TABLE IF NOT EXISTS script_setting (script TEXT NOT NULL, name TEXT NOT NULL, value BLOB, PRIMARY KEY(script, name));")
      Lich.db.execute("CREATE TABLE IF NOT EXISTS script_auto_settings (script TEXT NOT NULL, scope TEXT, hash BLOB, PRIMARY KEY(script, scope));")
      Lich.db.execute("CREATE TABLE IF NOT EXISTS lich_settings (name TEXT NOT NULL, value TEXT, PRIMARY KEY(name));")
      Lich.db.execute("CREATE TABLE IF NOT EXISTS uservars (scope TEXT NOT NULL, hash BLOB, PRIMARY KEY(scope));")
      Lich.db.execute("CREATE TABLE IF NOT EXISTS simu_game_entry (character TEXT NOT NULL, game_code TEXT NOT NULL, data BLOB, PRIMARY KEY(character, game_code));")
      Lich.db.execute("CREATE TABLE IF NOT EXISTS enable_inventory_boxes (player_id INTEGER NOT NULL, PRIMARY KEY(player_id));")
    rescue SQLite3::BusyException
      sleep 0.1
      retry
    end
  end

  def Lich.class_variable_get(*a); nil; end
  def Lich.class_eval(*a);         nil; end
  def Lich.module_eval(*a);        nil; end

  def Lich.log(msg)
    $stderr.puts "#{Time.now.strftime("%Y-%m-%d %H:%M:%S")}: #{msg}"
  end


  def Lich.inventory_boxes(player_id)
   begin
     !!Lich.db.get_first_value('SELECT player_id FROM enable_inventory_boxes WHERE player_id=?;', player_id.to_i)
   rescue SQLite3::BusyException
       sleep 0.1
       retry
   end
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
