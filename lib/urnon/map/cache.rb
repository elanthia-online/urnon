require 'urnon/lich/string-proc'
require 'urnon/map/room'
require 'digest'
require 'urnon/util/format'

module Map
  module Cache
    @lock  = Mutex.new
    @by_fingerprint ||= {}
    # for O(1) lookups by id
    @by_id  ||= {}
    # for O(1) lookups by tag
    @by_tag ||= {}

    @by_title ||= {}
    @by_description ||= {}
    # invalid dropped rooms during decoding
    @dropped ||= {}


    class << self
      include Enumerable

      def each()
        @by_id.values.each {|room| yield(room)}
      end
    end

    def self.size()
      @by_id.size
    end

    def self.empty?
      @by_id.empty?
    end

    def self.clear
      self.access {
        [@by_id, @by_tag, @by_fingerprint, @by_title, @by_description, @dropped].each(&:clear)
      }
    end

    def self.list()
      @by_id.values
    end

    def self.json_files()
      Dir["#{DATA_DIR}/#{Session.current.xml_data.game}/map*.json"].sort#.reverse
    end

    def self.load(**kwargs)
      file = kwargs[:file]
      return true if self.size > 0 && !kwargs.fetch(:force, false)
      self.clear  if self.size > 0
      return self.load_json(**kwargs) if file

      if json_files.empty?
        echo "error: no mapdb found"
        return false
      end

      map_candidate = self.json_files.find {|file| File.exist?(file) }
      return false if map_candidate.nil?
      load_time = Benchmark.realtime { self.load_json(file: map_candidate) }
      puts "loaded %s in %s" % [map_candidate, Format.time(load_time)]
    end

    def self.access()
      @lock.synchronize {yield}
    end

    def self.load_json(file: nil, limit: 100_000)
      self.access {
        f = File.open(file)
        JSON.parse(f.read).slice(0, limit).each { |room|
          room['wayto'].keys.each { |k|
            if room['wayto'][k][0..2] == ';e '
              room['wayto'][k] = StringProc.new(room['wayto'][k][3..-1])
            end
          }

          room['timeto'].keys.each { |k|
            if room['timeto'][k].is_a?(String) && room['timeto'][k].start_with?(";e ")
              room['timeto'][k] = StringProc.new(room['timeto'][k][3..-1])
            end
          }
          self.insert Room::Record.new(**room)
        }
      }
    end

    def self.drop(room)
      @dropped[room.id || :missing_id] = room
    end

    def self.dropped?(id)
      @dropped[id || :missing_id]
    end

    def self.insert(room)
      return self.drop(room) unless room.valid?
      @by_id[room.id] = room
      room.title.map(&:strip).each {|title|
        @by_title[title] ||= []
        @by_title[title] << room
      }

      room.description.map(&:strip).each {|desc|
        @by_description[desc] ||= []
        @by_description[desc] << room
      }

      build_tag_search(room) if room.tags.is_a?(Array) && room.tags.size > 0
      begin
        build_finger_print_search(room)
      rescue => exception
        puts "could not build fingerprints for #{room} valid?=#{room.valid?}"
        puts exception.message
        puts exception.backtrace.join("\n")
      end
    end

    def self.build_finger_print_search(room)
      fingerprints = self.build_fingerprints(room)
      fingerprints.each {|fingerprint|
        @by_fingerprint[fingerprint] ||= []
        @by_fingerprint[fingerprint] << room
      }
    end

    def self.build_fingerprints(room)
      room.title.product(
        room.description,
        room.paths).map {|variant|
        title, description, paths = variant
        self.fingerprint_of(title: title,
                            description: description,
                            paths: paths)
      }
    end

    def self.fingerprint_of(title:, description:, paths:)
      [title, description, paths]
        .map(&:strip)
        .join("/")
    end

    def self.build_tag_search(room)
      room.tags.each {|tag|
        @by_tag[tag] ||= []
        @by_tag[tag] << room
      }
    end

    def self.by_id
      @by_id
    end

    def self.by_tag
      @by_tag
    end

    def self.by_title
      @by_title
    end

    def self.by_description
      @by_description
    end

    def self.by_fingerprint
      @by_fingerprint
    end

    def self.find_by_fingerprint(**context)
      @by_fingerprint.fetch(
        self.fingerprint_of(**context),
        [])
    end

    def self.tags
      @by_tag.keys
    end

    def self.current_room(session)
      title = session.xml_data.room_title.strip

      candidates = self.find_by_fingerprint(
        title:       title,
        description: session.xml_data.room_description.strip,
        paths:       session.xml_data.room_exits_string.strip
      )

      return candidates.first if candidates.size > 0
      title_match = @by_title[title]
      return title_match.first if title_match.size.eql?(1)
      # todo: handle peer case
      return nil
    end

    def self.fzf(val)
      return nil if val.nil?
      if (val.class == Fixnum) or (val.class == Bignum) or val =~ /^[0-9]+$/
        self.by_id[val.to_i]
      else
        chkre = /#{val.strip.sub(/\.$/, '').gsub(/\.(?:\.\.)?/, '|')}/i
        chk = /#{Regexp.escape(val.strip)}/i
        self.find { |room| room.title.find { |title| title =~ chk } } ||
        self.find { |room| room.description.find { |desc| desc =~ chk } } ||
        self.find { |room| room.description.find { |desc| desc =~ chkre } }
      end
    end

    def self.[](val)
      self.fzf(val)
    end

    def self.dijkstra(source, destination=nil)
      source = self.fzf(source) unless source.is_a?(Room::Record)
      return source.dijkstra(destination) if source.is_a?(Room::Record)
      echo "self.dijkstra: error: invalid source room"
      nil
    end
  end
end
