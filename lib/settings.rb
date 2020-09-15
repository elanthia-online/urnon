
module Settings
  @settings    = Hash.new
  @md5_at_load = Hash.new
  @mutex       = Mutex.new

  Thread.new {
    self[:name] = "settings:save"
    loop {
      begin
        sleep 10
        Settings.save()
      rescue
        Lich.log "error: #{$!}\n\t#{$!.backtrace.join("\n\t")}"
        respond "--- Lich: error: #{$!}\n\t#{$!.backtrace[0..1].join("\n\t")}"
      end
    }
  }

  def self.get(scope)
    Script.current do |script|
      @mutex.synchronize {
        unless @settings[script.name] and @settings[script.name][scope]
          begin
            _hash = Lich.db.get_first_value(
              'SELECT hash FROM script_auto_settings WHERE script=? AND scope=?;', 
              script.name.encode('UTF-8'), 
              scope.encode('UTF-8'))
          rescue SQLite3::BusyException
            sleep 0.1
            retry
          end
          @settings[script.name] ||= Hash.new
          if _hash.nil?
            @settings[script.name][scope] = Hash.new
          else
            begin
              hash = Marshal.load(_hash)
            rescue
              respond "--- Lich: error: #{$!}"
              respond $!.backtrace[0..1]
              respond "... cleaning up bad data"
              hash = {}
            end
            @settings[script.name][scope] = hash
          end
          @md5_at_load[script.name] ||= Hash.new
          @md5_at_load[script.name][scope] = Digest::MD5.hexdigest(@settings[script.name][scope].to_s)
        end
      }
      @settings[script.name][scope]
    end
  end

  def Settings.[](name)
     Settings.get(':')[name]
  end
  
  def Settings.[]=(name, value)
     Settings.get(':')[name] = value
  end

  def Settings.load()
   # noop
  end
  
  def Settings.to_hash(scope=':')
     Settings.get(scope)
  end
  
  def Settings.char
     Settings.get("#{XMLData.game}:#{XMLData.name}")
  end

  def Settings.save()
    @mutex.synchronize {
      sql_began = false
      @settings.each_pair { |script_name,scopedata|
         scopedata.each_pair { |scope,data|
            if Digest::MD5.hexdigest(data.to_s) != @md5_at_load[script_name][scope]
               unless sql_began
                  begin
                     Lich.db.execute('BEGIN')
                  rescue SQLite3::BusyException
                     sleep 0.1
                     retry
                  end
                  sql_began = true
               end
               blob = SQLite3::Blob.new(Marshal.dump(data))
               begin
                  Lich.db.execute(
                    'INSERT OR REPLACE INTO script_auto_settings(script,scope,hash) VALUES(?,?,?);', 
                    script_name.encode('UTF-8'), 
                    scope.encode('UTF-8'), 
                    blob)
               rescue SQLite3::BusyException
                  sleep 0.1
                  retry
               rescue
                  respond "--- Lich: error: #{$!}"
                  respond $!.backtrace[0..1]
                  next
               end
            end
         }
         unless Script.running?(script_name)
            @settings.delete(script_name)
            @md5_at_load.delete(script_name)
         end
      }
      if sql_began
         begin
            Lich.db.execute('END')
         rescue SQLite3::BusyException
            sleep 0.1
            retry
         end
      end
   }
  end
end