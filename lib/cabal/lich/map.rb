require "json"
require "digest"
require 'cabal/session'

class Map
   LOCK ||= Mutex.new
   @@loaded                 ||= false

   # todo: get rid of all these duplicate references
   @@load_mutex             ||= Map::LOCK
   @@current_room_mutex     ||= Map::LOCK
   @@fuzzy_room_mutex       ||= Map::LOCK

   @@list                   ||= Array.new
   @@tags                   ||= Array.new

   # this is a cache id
   @@cache_checksum         ||= -1
   # only perform expensive DB lookups when
   # the Session.current.xml_data.room_count changes after the first
   @@cached_room_id         ||= nil

   @@current_room_id        ||= 0
   @@current_room_count     ||= -1

   @@fuzzy_room_id          ||= 0
   @@fuzzy_room_count       ||= -1

   @@current_location       ||= nil
   @@current_location_count ||= -1

   attr_reader :id
   attr_accessor :title, :description, :paths,
                 :location, :climate, :terrain, :wayto,
                 :timeto, :image, :image_coords, :tags,
                 :check_location, :unique_loot

   def initialize(id, title, description, paths, location=nil, climate=nil, terrain=nil, wayto={}, timeto={}, image=nil, image_coords=nil, tags=[], check_location=nil, unique_loot=nil)
      @id, @title, @description, @paths, @location,
      @climate, @terrain, @wayto, @timeto, @image, @image_coords, @tags,
      @check_location, @unique_loot = id, title, description, paths, location, climate, terrain, wayto, timeto, image, image_coords, tags, check_location, unique_loot
      @@list[@id] = self
   end

   def outside?
      @paths.first =~ /Obvious paths:/
   end

   def to_i
      @id
   end

   def to_s
      "##{@id}:\n#{@title[-1]}\n#{@description[-1]}\n#{@paths[-1]}"
   end

   def inspect
      self.instance_variables.collect { |var|
         var.to_s + "=" + self.instance_variable_get(var).inspect
      }.join("\n")
   end

   def Map.get_free_id
      Map.load unless @@loaded
      free_id = 0
      free_id += 1 until @@list[free_id].nil?
      free_id
   end

   def Map._state()
      {current_room_id: @@current_room_id,
       current_room_count: @@current_room_count,
       fuzzy_room_id: @@fuzzy_room_id,
       fuzzy_room_count: @@fuzzy_room_count,
       current_location: @@current_location,
       current_location_count: @@current_location_count,
       loaded: @@loaded,
      }
   end

   def Map.list
      Map.load unless @@loaded
      @@list
   end

   def Map.[](val)
      Map.load unless @@loaded
      return nil if val.nil?
      if (val.class == Fixnum) or (val.class == Bignum) or val =~ /^[0-9]+$/
         @@list[val.to_i]
      else
         chkre = /#{val.strip.sub(/\.$/, '').gsub(/\.(?:\.\.)?/, '|')}/i
         chk = /#{Regexp.escape(val.strip)}/i
         @@list.find { |room| room.title.find { |title| title =~ chk } } || @@list.find { |room| room.description.find { |desc| desc =~ chk } } || @@list.find { |room| room.description.find { |desc| desc =~ chkre } }
      end
   end

   def Map.get_location
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

   FOGGY_EXITS = /^Obvious (?:exits|paths): obscured by a thick fog$/

   def Map.strict_lookup_from_xml()
     foggy_exits = (Session.current.xml_data.room_exits_string =~ FOGGY_EXITS)
     @@list.find { |r|
       r.title.include?(Session.current.xml_data.room_title) and
       r.description.include?(Session.current.xml_data.room_description.strip) and
       (r.unique_loot.nil? or (r.unique_loot.to_a - GameObj.loot.to_a.collect { |obj| obj.name }).empty?) and
       (foggy_exits or r.paths.include?(Session.current.xml_data.room_exits_string.strip) or r.tags.include?('random-paths')) and
       (not r.check_location or r.location == Map.get_location)
      }
   end

   def Map.fzf_from_xml()
      1.times {
         @@fuzzy_room_count = Session.current.xml_data.room_count
         foggy_exits = (Session.current.xml_data.room_exits_string =~ FOGGY_EXITS)
         if (room = @@list.find { |r| r.title.include?(Session.current.xml_data.room_title) and r.description.include?(Session.current.xml_data.room_description.strip) and (r.unique_loot.nil? or (r.unique_loot.to_a - GameObj.loot.to_a.collect { |obj| obj.name }).empty?) and (foggy_exits or r.paths.include?(Session.current.xml_data.room_exits_string.strip) or r.tags.include?('random-paths')) and (not r.check_location or r.location == Map.get_location) })
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
            if room = @@list.find { |r| r.title.include?(Session.current.xml_data.room_title) and (foggy_exits or r.paths.include?(Session.current.xml_data.room_exits_string.strip) or r.tags.include?('random-paths')) and (Session.current.xml_data.room_window_disabled or r.description.any? { |desc| desc =~ desc_regex }) and (r.unique_loot.nil? or (r.unique_loot.to_a - GameObj.loot.to_a.collect { |obj| obj.name }).empty?) and (not r.check_location or r.location == Map.get_location) }
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

   def Map.current_checksum()
      Digest::SHA2.hexdigest(
         Session.current.xml_data.room_count.to_s + Session.current.xml_data.room_title + Session.current.xml_data.room_description)
   end

   def Map.cached?(checksum)
      checksum.eql? @@cache_checksum
   end

   def Map.loaded?
      @@loaded
   end

   def self.updating?
     Session.current.xml_data.updating_room?
   end

   def Map.current()
      Map.load unless Map.loaded?
      Map::LOCK.synchronize {
         1.times {
            sleep 0.1 while Session.current.xml_data.updating_room?
            starting_checksum = Map.current_checksum()
            return Map[@@cached_room_id] if Map.cached?(starting_checksum)
            @@cache_checksum = starting_checksum
            # todo: this could be at worst O(4) operation instead of O(Map.list.size)
            current_room = Map.strict_lookup_from_xml || Map.fzf_from_xml
            ending_checksum = Map.current_checksum
            # retry if we are mid room update
            redo unless starting_checksum.eql?(ending_checksum)
            redo if Session.current.xml_data.updating_room?
            @@cached_room_id = current_room.nil? ? nil : current_room.id
            return current_room
         }
      }
   end

   def Map.current_or_new
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
      current_location = Map.get_location
      if room = @@list.find { |r| (r.location == current_location) and r.title.include?(Session.current.xml_data.room_title) and r.description.include?(Session.current.xml_data.room_description.strip) and (r.unique_loot.nil? or (r.unique_loot.to_a - GameObj.loot.to_a.collect { |obj| obj.name }).empty?) and (r.paths.include?(Session.current.xml_data.room_exits_string.strip) or r.tags.include?('random-paths')) and check_peer_tag.call(r) }
         return room
      elsif room = @@list.find { |r| r.location.nil? and r.title.include?(Session.current.xml_data.room_title) and r.description.include?(Session.current.xml_data.room_description.strip) and (r.unique_loot.nil? or (r.unique_loot.to_a - GameObj.loot.to_a.collect { |obj| obj.name }).empty?) and (r.paths.include?(Session.current.xml_data.room_exits_string.strip) or r.tags.include?('random-paths')) and check_peer_tag.call(r) }
         room.location = current_location
         return room
      else
         title = [ Session.current.xml_data.room_title ]
         description = [ Session.current.xml_data.room_description.strip ]
         paths = [ Session.current.xml_data.room_exits_string.strip ]
         room = Map.new(Map.get_free_id, title, description, paths, current_location)
         identical_rooms = @@list.find_all { |r| (r.location != current_location) and r.title.include?(Session.current.xml_data.room_title) and r.description.include?(Session.current.xml_data.room_description.strip) and (r.unique_loot.nil? or (r.unique_loot.to_a - GameObj.loot.to_a.collect { |obj| obj.name }).empty?) and (r.paths.include?(Session.current.xml_data.room_exits_string.strip) or r.tags.include?('random-paths')) }
         if identical_rooms.length > 0
            room.check_location = true
            identical_rooms.each { |r| r.check_location = true }
         end
         return room
      end
   end

   def Map.tags
      Map.load unless @@loaded
      if @@tags.empty?
         @@list.each { |r| r.tags.each { |t| @@tags.push(t) unless @@tags.include?(t) } }
      end
      @@tags.dup
   end

   def Map.clear
      @@load_mutex.synchronize {
         @@list.clear
         @@tags.clear
         @@loaded = false
         GC.start
      }
      true
   end

   def Map.reload
      Map.clear
      Map.load
   end

   def Map.json_files()
      Dir["#{DATA_DIR}/#{Session.current.xml_data.game}/map*.json"]
   end

   def Map.load(filename=nil)
     return Map.load_json(filename) if filename

     if json_files.empty?
      echo "error: no mapdb found"
      return false
     end

     for filename in Map.json_files()
      return true if Map.load_json(filename)
     end

     return false
   end

   def Map.load_json(filename=nil)
      @@load_mutex.synchronize {
         return true if @@loaded

         filename ||= Map.json_files.sort.first

         if filename.nil?
            puts "--- Lich: error: no map database found"
            return false
         end
         puts "-- Lich: loading mapdb from %s" % filename
         File.open(filename) { |f|
            JSON.parse(f.read).each { |room|
               room['wayto'].keys.each { |k|
                  if room['wayto'][k][0..2] == ';e '
                     room['wayto'][k] = StringProc.new(room['wayto'][k][3..-1])
                  end
               }
               room['timeto'].keys.each { |k|
                  if (room['timeto'][k].class == String) and (room['timeto'][k][0..2] == ';e ')
                     room['timeto'][k] = StringProc.new(room['timeto'][k][3..-1])
                  end
               }
               Map.new( room['id'],
                        room['title'],
                        room['description'],
                        room['paths'],
                        room['location'],
                        room['climate'],
                        room['terrain'],
                        room['wayto'],
                        room['timeto'],
                        room['image'],
                        room['image_coords'],
                        room['tags'],
                        room['check_location'],
                        room['unique_loot'])
            }
         }
         @@tags.clear
         @@loaded = true
         return @@loaded
      }
   end

   def Map.to_json(*args)
      @@list.delete_if { |r| r.nil? }
      @@list.to_json(args)
   end

   def to_json(*args)
      ({
         :id => @id,
         :title => @title,
         :description => @description,
         :paths => @paths,
         :location => @location,
         :climate => @climate,
         :terrain => @terrain,
         :wayto => @wayto,
         :timeto => @timeto,
         :image => @image,
         :image_coords => @image_coords,
         :tags => @tags,
         :check_location => @check_location,
         :unique_loot => @unique_loot
      }).delete_if { |a,b| b.nil? or (b.class == Array and b.empty?) }.to_json(args)
   end

   def Map.save_json(filename="#{DATA_DIR}/#{Session.current.xml_data.game}/map-#{Time.now.to_i}.json")
      if File.exists?(filename)
         puts "File exists!  Backing it up before proceeding..."
         begin
            File.open(filename, 'rb') { |infile|
               File.open("#{filename}.bak", "wb") { |outfile|
                  outfile.write(infile.read)
               }
            }
         rescue
            puts "--- Lich: error: #{$!}\n\t#{$!.backtrace[0..1].join("\n\t")}"
            Lich.log "error: #{$!}\n\t#{$!.backtrace.join("\n\t")}"
         end
      end
      File.open(filename, 'wb') { |file|
         file.write(Map.to_json)
      }
   end

   def Map.estimate_time(array)
      Map.load unless @@loaded
      unless array.class == Array
         raise Exception.exception("MapError"), "Map.estimate_time was given something not an array!"
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

   def Map.dijkstra(source, destination=nil)
      if source.class == Map
         source.dijkstra(destination)
      elsif room = Map[source]
         room.dijkstra(destination)
      else
         echo "Map.dijkstra: error: invalid source room"
         nil
      end
   end

   def dijkstra(destination=nil)
      begin
         Map.load unless @@loaded
         source = @id
         visited = Array.new
         shortest_distances = Array.new
         previous = Array.new
         pq = [ source ]
         pq_push = proc { |val|
            for i in 0...pq.size
               if shortest_distances[val] <= shortest_distances[pq[i]]
                  pq.insert(i, val)
                  break
               end
            end
            pq.push(val) if i.nil? or (i == pq.size-1)
         }
         visited[source] = true
         shortest_distances[source] = 0
         if destination.nil?
            until pq.size == 0
               v = pq.shift
               visited[v] = true
               @@list[v].wayto.keys.each { |adj_room|
                  adj_room_i = adj_room.to_i
                  unless visited[adj_room_i]
                     if @@list[v].timeto[adj_room].class == Proc
                        nd = @@list[v].timeto[adj_room].call
                     else
                        nd = @@list[v].timeto[adj_room]
                     end
                     if nd
                        nd += shortest_distances[v]
                        if shortest_distances[adj_room_i].nil? or (shortest_distances[adj_room_i] > nd)
                           shortest_distances[adj_room_i] = nd
                           previous[adj_room_i] = v
                           pq_push.call(adj_room_i)
                        end
                     end
                  end
               }
            end
         elsif destination.class == Fixnum
            until pq.size == 0
               v = pq.shift
               break if v == destination
               visited[v] = true
               @@list[v].wayto.keys.each { |adj_room|
                  adj_room_i = adj_room.to_i
                  unless visited[adj_room_i]
                     if @@list[v].timeto[adj_room].class == Proc
                        nd = @@list[v].timeto[adj_room].call
                     else
                        nd = @@list[v].timeto[adj_room]
                     end
                     if nd
                        nd += shortest_distances[v]
                        if shortest_distances[adj_room_i].nil? or (shortest_distances[adj_room_i] > nd)
                           shortest_distances[adj_room_i] = nd
                           previous[adj_room_i] = v
                           pq_push.call(adj_room_i)
                        end
                     end
                  end
               }
            end
         elsif destination.class == Array
            dest_list = destination.collect { |dest| dest.to_i }
            until pq.size == 0
               v = pq.shift
               break if dest_list.include?(v) and (shortest_distances[v] < 20)
               visited[v] = true
               @@list[v].wayto.keys.each { |adj_room|
                  adj_room_i = adj_room.to_i
                  unless visited[adj_room_i]
                     if @@list[v].timeto[adj_room].class == Proc
                        nd = @@list[v].timeto[adj_room].call
                     else
                        nd = @@list[v].timeto[adj_room]
                     end
                     if nd
                        nd += shortest_distances[v]
                        if shortest_distances[adj_room_i].nil? or (shortest_distances[adj_room_i] > nd)
                           shortest_distances[adj_room_i] = nd
                           previous[adj_room_i] = v
                           pq_push.call(adj_room_i)
                        end
                     end
                  end
               }
            end
         end
         return previous, shortest_distances
      rescue
         echo "Map.dijkstra: error: #{$!}"
         puts $!.backtrace
         nil
      end
   end

   def Map.findpath(source, destination)
      if source.class == Map
         source.path_to(destination)
      elsif room = Map[source]
         room.path_to(destination)
      else
         echo "Map.findpath: error: invalid source room"
         nil
      end
   end

   def path_to(destination)
      Map.load unless @@loaded
      destination = destination.to_i
      previous, _shortest_distances = dijkstra(destination)
      return nil unless previous[destination]
      path = [ destination ]
      path.push(previous[path[-1]]) until previous[path[-1]] == @id
      path.reverse!
      path.pop
      return path
   end

   def find_nearest_by_tag(tag_name)
      target_list = Array.new
      @@list.each { |room| target_list.push(room.id) if room.tags.include?(tag_name) }
      _previous, shortest_distances = Map.dijkstra(@id, target_list)
      if target_list.include?(@id)
         @id
      else
         target_list.delete_if { |room_num| shortest_distances[room_num].nil? }
         target_list.sort { |a,b| shortest_distances[a] <=> shortest_distances[b] }.first
      end
   end

   def find_all_nearest_by_tag(tag_name)
      target_list = Array.new
      @@list.each { |room| target_list.push(room.id) if room.tags.include?(tag_name) }
      _previous, shortest_distances = Map.dijkstra(@id)
      target_list.delete_if { |room_num| shortest_distances[room_num].nil? }
      target_list.sort { |a,b| shortest_distances[a] <=> shortest_distances[b] }
   end

   def find_nearest(target_list)
      target_list = target_list.collect { |num| num.to_i }
      if target_list.include?(@id)
         @id
      else
         _previous, shortest_distances = Map.dijkstra(@id, target_list)
         target_list.delete_if { |room_num| shortest_distances[room_num].nil? }
         target_list.sort { |a,b| shortest_distances[a] <=> shortest_distances[b] }.first
      end
   end
end

class Map
   def desc
      @description
   end
   def map_name
      @image
   end
   def map_x
      if @image_coords.nil?
         nil
      else
         ((image_coords[0] + image_coords[2])/2.0).round
      end
   end
   def map_y
      if @image_coords.nil?
         nil
      else
         ((image_coords[1] + image_coords[3])/2.0).round
      end
   end
   def map_roomsize
      if @image_coords.nil?
         nil
      else
         image_coords[2] - image_coords[0]
      end
   end
   def geo
      nil
   end
end
