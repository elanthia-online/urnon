require "json"
require "digest"
require 'urnon/session'
require 'urnon/map/cache'

class Room
  class Record
    attr_accessor :id, :title, :description, :paths,
                  :location, :climate, :terrain, :wayto,
                  :timeto, :image, :image_coords, :tags,
                  :check_location, :unique_loot

    def initialize(**vars)
      vars.each {|k, v| self.instance_variable_set("@%s" % k, v) }
      @id = vars.fetch("id")
      proposed_paths = vars.fetch("paths", [])
      @paths = proposed_paths.is_a?(Array) ? proposed_paths : [proposed_paths]
    end

    def valid?
      self.id.is_a?(Integer) &&
      self.description.is_a?(Array) &&
      self.description.size > 0 &&
      self.title.is_a?(Array) &&
      self.title.size > 0 &&
      self.paths.is_a?(Array) &&
      self.paths.size > 0 &&
      self.description.all? { |desc| desc.is_a?(String) } &&
      self.title.all? {|title| title.is_a?(String)} &&
      self.paths.all? {|path| path.is_a?(String)}
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

    def dijkstra(destination=nil)
      visited            = []
      shortest_distances = []
      previous           = []
      source             = @id
      pq                 = [ source ]
      begin

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
            Map.find_by_id(v).wayto.keys.each { |adj_room|
              adj_room_i = adj_room.to_i
              unless visited[adj_room_i]
                if Map.find_by_id(v).timeto[adj_room].class == Proc
                  nd = Map.find_by_id(v).timeto[adj_room].call
                else
                  nd = Map.find_by_id(v).timeto[adj_room]
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
            Map.find_by_id(v).wayto.keys.each { |adj_room|
              adj_room_i = adj_room.to_i
              unless visited[adj_room_i]
                if Map.find_by_id(v).timeto[adj_room].class == Proc
                  nd = Map.find_by_id(v).timeto[adj_room].call
                else
                  nd = Map.find_by_id(v).timeto[adj_room]
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
            Map.find_by_id(v).wayto.keys.each { |adj_room|
              adj_room_i = adj_room.to_i
              unless visited[adj_room_i]
                if Map.find_by_id(v).timeto[adj_room].class == Proc
                  nd = Map.find_by_id(v).timeto[adj_room].call
                else
                  nd = Map.find_by_id(v).timeto[adj_room]
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
        respond "Room::record.dijkstra: error: #{$!}"
        respond "visited.last=%s\nsource=%s\npq.last=%s" % [visited.last, source, pq.last]
        respond $!.backtrace.join("\n")
        nil
      end
    end

    def path_to(destination)
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
      target_list = Map.find_by_tag(tag_name.to_s).map(&:id)
      _previous, shortest_distances = Map.dijkstra(@id, target_list)
      if target_list.include?(@id)
        @id
      else
        target_list.delete_if { |room_num| shortest_distances[room_num].nil? }
        target_list.sort { |a,b| shortest_distances[a] <=> shortest_distances[b] }.first
      end
    end

    def find_all_nearest_by_tag(tag_name)
      target_list = Map.find_by_tag(tag_name.to_s).map(&:id)
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

    def to_h
      self.instance_variables.each_with_object({}) {|var, acc|
        val = self.instance_variable_get(var)
        unless val.nil? || (val.is_a?(Array) && val.empty?)
          acc[var.to_s.slice(1..-1)] = val
        end
      }
    end

    def to_json(...)
      self.to_h.to_json(...)
    end

    def [](prop)
      self.instance_variable_get("@%s" % prop)
    end
  end
end
