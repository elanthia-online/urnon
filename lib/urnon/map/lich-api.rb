module Map
  class LichAPI
    LOCK = Mutex.new
    FOGGY_EXITS = /^Obvious (?:exits|paths): obscured by a thick fog$/
    @@cache_checksum = nil
    @@cached_room_id = nil

    def self.get_location
      unless Session.current.xml_data.room_count == @@current_location_count
      if script = Script.current
      save_want_downstream = script.want_downstream
      script.want_downstream = true
      waitrt?
      location_result = dothistimeout 'location', 15, /^You carefully survey your surroundings and guess that your current location is .*? or somewhere close to it\.$|^You can't do that while submerged under water\.$|^You can't do that\.$|^It would be rude not to give your full attention to the performance\.$|^You can't do that while hanging around up here!$|^You are too distracted by the difficulty of staying alive in these treacherous waters to do that\.$|^You carefully survey your surroundings but are unable to guess your current location\.$|^Not in pitch darkness you don't\.$|^That is too difficult to consider here\.$/
        script.want_downstream = save_want_downstream
        @@current_location_count = Session.current.xml_data.room_count
        if location_result =~ /^You can't do that while submerged under water\.$|^You can't do that\.$|^It would be rude not to give your full attention to the performance\.$|^You can't do that while hanging around up here!$|^You are too distracted by the difficulty of staying alive in these treacherous waters to do that\.$|^You carefully survey your surroundings but are unable to guess your current location\.$|^Not in pitch darkness you don't\.$|^That is too difficult to consider here\.$/
          @@current_location = false
        else
          @@current_location = /^You carefully survey your surroundings and guess that your current location is (.*?) or somewhere close to it\.$/.match(location_result).captures.first
        end
      else
        nil
      end
      end
      @@current_location
    end

    def self.strict_lookup_from_xml()
      foggy_exits = (Session.current.xml_data.room_exits_string =~ FOGGY_EXITS)
      MapCache.list.find { |r|
      r.title.include?(Session.current.xml_data.room_title) and
      r.description.include?(Session.current.xml_data.room_description.strip) and
      (r.unique_loot.nil? or (r.unique_loot.to_a - GameObj.loot.to_a.collect { |obj| obj.name }).empty?) and
      (foggy_exits or r.paths.include?(Session.current.xml_data.room_exits_string.strip) or r.tags.include?('random-paths')) and
      (not r.check_location or r.location == self.get_location)
      }
    end

    def self.fzf_from_xml()
      1.times {
      @@fuzzy_room_count = Session.current.xml_data.room_count
      foggy_exits = (Session.current.xml_data.room_exits_string =~ FOGGY_EXITS)
      if (room = MapCache.list.find { |r| r.title.include?(Session.current.xml_data.room_title) and r.description.include?(Session.current.xml_data.room_description.strip) and (r.unique_loot.nil? or (r.unique_loot.to_a - GameObj.loot.to_a.collect { |obj| obj.name }).empty?) and (foggy_exits or r.paths.include?(Session.current.xml_data.room_exits_string.strip) or r.tags.include?('random-paths')) and (not r.check_location or r.location == self.get_location) })
        redo unless @@fuzzy_room_count == Session.current.xml_data.room_count
        if room.tags.any? { |tag| tag =~ /^(set desc on; )?peer [a-z]+ =~ \/.+\/$/ }
          @@fuzzy_room_id = nil
          return nil
        else
          @@fuzzy_room_id = room.id
          return room
        end
      else
        redo unless @@fuzzy_room_count == Session.current.xml_data.room_count
        desc_regex = /#{Regexp.escape(Session.current.xml_data.room_description.strip.sub(/\.+$/, '')).gsub(/\\\.(?:\\\.\\\.)?/, '|')}/
        if room = MapCache.list.find { |r| r.title.include?(Session.current.xml_data.room_title) and (foggy_exits or r.paths.include?(Session.current.xml_data.room_exits_string.strip) or r.tags.include?('random-paths')) and (Session.current.xml_data.room_window_disabled or r.description.any? { |desc| desc =~ desc_regex }) and (r.unique_loot.nil? or (r.unique_loot.to_a - GameObj.loot.to_a.collect { |obj| obj.name }).empty?) and (not r.check_location or r.location == self.get_location) }
          redo unless @@fuzzy_room_count == Session.current.xml_data.room_count
          if room.tags.any? { |tag| tag =~ /^(set desc on; )?peer [a-z]+ =~ \/.+\/$/ }
            @@fuzzy_room_id = nil
            return nil
          else
            @@fuzzy_room_id = room.id
            return room
          end
        else
          redo unless @@fuzzy_room_count == Session.current.xml_data.room_count
          @@fuzzy_room_id = nil
          return nil
        end
      end
      }
    end

    def self.current_checksum()
      Digest::SHA2.hexdigest(
        Session.current.xml_data.room_count.to_s + Session.current.xml_data.room_title + Session.current.xml_data.room_description)
    end

    def self.cached?(checksum)
      checksum.eql? @@cache_checksum
    end

    def self.updating?
      Session.current.xml_data.updating_room?
    end

    def self.current()
      LOCK.synchronize {
        1.times {
          sleep 0.1 while Session.current.xml_data.updating_room?
          starting_checksum = self.current_checksum()
          return self[@@cached_room_id] if self.cached?(starting_checksum)
          @@cache_checksum = starting_checksum
          # todo: this could be at worst O(4) operation instead of O(self.list.size)
          current_room = self.strict_lookup_from_xml || self.fzf_from_xml
          ending_checksum = self.current_checksum
          # retry if we are mid room update
          redo unless starting_checksum.eql?(ending_checksum)
          redo if Session.current.xml_data.updating_room?
          @@cached_room_id = current_room.nil? ? nil : current_room.id
          return current_room
        }
      }
    end

    def self.current_or_new
      return nil unless Script.current
      check_peer_tag = proc { |r|
      if peer_tag = r.tags.find { |tag| tag =~ /^(set desc on; )?peer [a-z]+ =~ \/.+\/$/ }
        good = false
        need_desc, peer_direction, peer_requirement = /^(set desc on; )?peer ([a-z]+) =~ \/(.+)\/$/.match(peer_tag).captures
        if need_desc && Script.current && Script.current.session
          unless last_roomdesc = Script.current.session.server_buffer.reverse.find { |line| line =~ /<style id="roomDesc"\/>/ } and (last_roomdesc =~ /<style id="roomDesc"\/>[^<]/)
            put 'set description on'
          end
        end
        script = Script.current
        save_want_downstream = script.want_downstream
        script.want_downstream = true
        squelch_started = false
        squelch_proc = proc { |server_string|
          if squelch_started
            if server_string =~ /<prompt/
              DownstreamHook.remove('squelch-peer')
            end
            nil
          elsif server_string =~ /^You peer/
            squelch_started = true
            nil
          else
            server_string
          end
        }
        DownstreamHook.add('squelch-peer', squelch_proc)
        result = dothistimeout "peer #{peer_direction}", 3, /^You peer|^\[Usage: PEER/
          if result =~ /^You peer/
            peer_results = Array.new
            5.times {
              if line = get?
                peer_results.push line
                break if line =~ /^Obvious/
              end
            }
            if peer_results.any? { |line| line =~ /#{peer_requirement}/ }
              good = true
            end
          end
          script.want_downstream = save_want_downstream
        else
          good = true
        end
        good
      }
      current_location = self.get_location
      if room = MapCache.list.find { |r| (r.location == current_location) and r.title.include?(Session.current.xml_data.room_title) and r.description.include?(Session.current.xml_data.room_description.strip) and (r.unique_loot.nil? or (r.unique_loot.to_a - GameObj.loot.to_a.collect { |obj| obj.name }).empty?) and (r.paths.include?(Session.current.xml_data.room_exits_string.strip) or r.tags.include?('random-paths')) and check_peer_tag.call(r) }
        return room
      elsif room = MapCache.list.find { |r| r.location.nil? and r.title.include?(Session.current.xml_data.room_title) and r.description.include?(Session.current.xml_data.room_description.strip) and (r.unique_loot.nil? or (r.unique_loot.to_a - GameObj.loot.to_a.collect { |obj| obj.name }).empty?) and (r.paths.include?(Session.current.xml_data.room_exits_string.strip) or r.tags.include?('random-paths')) and check_peer_tag.call(r) }
        room.location = current_location
        return room
      else
        title = [ Session.current.xml_data.room_title ]
        description = [ Session.current.xml_data.room_description.strip ]
        paths = [ Session.current.xml_data.room_exits_string.strip ]
        room = self.new(self.get_free_id, title, description, paths, current_location)
        identical_rooms = MapCache.list.find_all { |r| (r.location != current_location) and r.title.include?(Session.current.xml_data.room_title) and r.description.include?(Session.current.xml_data.room_description.strip) and (r.unique_loot.nil? or (r.unique_loot.to_a - GameObj.loot.to_a.collect { |obj| obj.name }).empty?) and (r.paths.include?(Session.current.xml_data.room_exits_string.strip) or r.tags.include?('random-paths')) }
        if identical_rooms.length > 0
          room.check_location = true
          identical_rooms.each { |r| r.check_location = true }
        end
        return room
      end
    end

    def self.estimate_time(array)
      unless array.class == Array
        raise Exception.exception("MapError"), "self.estimate_time was given something not an array!"
      end
      time = 0.to_f
      until array.length < 2
        room = array.shift
        if t = Map[room].timeto[array.first.to_s]
          if t.class == Proc
            time += t.call.to_f
          else
            time += t.to_f
          end
        else
          time += "0.2".to_f
        end
      end
      time
    end
  end
end
