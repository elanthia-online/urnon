require 'cabal/lich/xml-parser'

module Cabal
  class Session
    SESSIONS ||= {}
    # inherit enumerable for all the goodness
    class << self
      include Enumerable
      def each()
        SESSIONS.each {|session|
          (name, session) = session
          yield(session, name)
        }
      end
    end

    def self.size()
      SESSIONS.size
    end

    def self.open(game_host, game_port, client_port)
      Session.new(game_host, game_port, client_port)
    end

    attr_reader :buffer, :_buffer, :xml_data,
                :game_socket, :game_thread, :last_recv,
                :client_thread, :client_sock, :client_port

    def initialize(game_host, game_port, client_port)
      @_lock     = Mutex.new
      @xml_data  = XMLParser.new(self)
      @buffer    = SharedBuffer.new
      @_buffer   = SharedBuffer.new
      @_buffer.max_size = 1000
      @client_port = client_port

      # TODO: deprecate globals
      $_SERVERBUFFER_ = @server_buffer = LimitedArray.new
      @server_buffer.max_size = 400
      $_CLIENTBUFFER_ = @client_buffer = LimitedArray.new
      @client_buffer.max_size = 100

      @game_socket = TCPSocket.open(game_host, game_port)
      begin
        @game_socket.setsockopt(Socket::SOL_SOCKET, Socket::SO_KEEPALIVE, true)
      rescue
        Lich.log "error: #{$!}\n\t#{$!.backtrace.join("\n\t")}"
      rescue Exception
        Lich.log "error: #{$!}\n\t#{$!.backtrace.join("\n\t")}"
      end
      @game_socket.sync = true
      # heart-beat check for the game socket
      @heartbeat = Thread.new {
        @last_recv = Time.now
        loop {
            if (@last_recv + 300) < Time.now
              Lich.log "#{Time.now}: error: nothing recieved from game server in 5 minutes"
              @game_thread.kill rescue nil
              break
            end
            sleep (300 - (Time.now - @last_recv))
            sleep 1
        }
      }

      @game_thread = Thread.new {
        begin
          atmospherics = false
          while $_SERVERSTRING_ = @game_socket.gets
            @last_recv = Time.now
            @_buffer.update($_SERVERSTRING_) if TESTING
            begin
                $cmd_prefix = String.new if $_SERVERSTRING_ =~ /^\034GSw/
                # The Rift, Scatter is broken...
                if $_SERVERSTRING_ =~ /<compDef id='room text'><\/compDef>/
                  $_SERVERSTRING_.sub!(/(.*)\s\s<compDef id='room text'><\/compDef>/)  { "<compDef id='room desc'>#{$1}</compDef>" }
                end
                if atmospherics
                  atmospherics = false
                  $_SERVERSTRING.prepend('<popStream id="atmospherics" \/>') unless $_SERVERSTRING =~ /<popStream id="atmospherics" \/>/
                end
                if $_SERVERSTRING_ =~ /<pushStream id="familiar" \/><prompt time="[0-9]+">&gt;<\/prompt>/ # Cry For Help spell is broken...
                  $_SERVERSTRING_.sub!('<pushStream id="familiar" />', '')
                elsif $_SERVERSTRING_ =~ /<pushStream id="atmospherics" \/><prompt time="[0-9]+">&gt;<\/prompt>/ # pet pigs in DragonRealms are broken...
                  $_SERVERSTRING_.sub!('<pushStream id="atmospherics" />', '')
                elsif ($_SERVERSTRING_ =~ /<pushStream id="atmospherics" \/>/)
                  atmospherics = true
                end

                $_SERVERBUFFER_.push($_SERVERSTRING_)
                if alt_string = DownstreamHook.run($_SERVERSTRING_)

                  if $_DETACHABLE_CLIENT_
                      begin
                        $_DETACHABLE_CLIENT_.write(alt_string)
                      rescue
                        $_DETACHABLE_CLIENT_.close rescue nil
                        $_DETACHABLE_CLIENT_ = nil
                        respond "--- Lich: error: client_thread: #{$!}"
                        respond $!.backtrace.first
                        Lich.log "error: client_thread: #{$!}\n\t#{$!.backtrace.join("\n\t")}"
                      end
                  end
                  if $frontend =~ /^(?:wizard|avalon)$/
                      alt_string = sf_to_wiz(alt_string)
                  end
                  $_CLIENT_.write(alt_string) unless $_CLIENT_.nil?
                end
                unless $_SERVERSTRING_ =~ /^<settings /
                  if $_SERVERSTRING_ =~ /^<settingsInfo .*?space not found /
                      $_SERVERSTRING_.sub!('space not found', '')
                  end
                  begin
                    #pp [$_SERVERSTRING_]
                    REXML::Document.parse_stream($_SERVERSTRING_, XMLData)
                  rescue
                      unless ($! || "").to_s =~ /invalid byte sequence/
                        if $_SERVERSTRING_ =~ /<[^>]+='[^=>'\\]+'[^=>']+'[\s>]/
                            # Simu has a nasty habbit of bad quotes in XML.  <tag attr='this's that'>
                            $_SERVERSTRING_.gsub!(/(<[^>]+=)'([^=>'\\]+'[^=>']+)'([\s>])/) { "#{$1}\"#{$2}\"#{$3}" }
                            retry
                        end
                        $stdout.puts "--- error: server_thread: #{$!}"
                        Lich.log "error: server_thread: #{$!}\n\t#{$!.backtrace.join("\n\t")}"
                      end
                      XMLData.reset
                  end
                  Script.new_downstream_xml($_SERVERSTRING_)
                  stripped_server = strip_xml($_SERVERSTRING_)
                  (stripped_server || "").split("\r\n").each { |line|
                      @buffer.update(line) if TESTING
                      Script.new_downstream(line) unless line.empty?
                  }
                end
            rescue
                $stdout.puts "--- error: server_thread: #{$!}"
                Lich.log "error: server_thread: #{$!}\n\t#{$!.backtrace.join("\n\t")}"
            end
          end
        rescue Exception => e
          Log.out(e, lable: :game_error)
          Lich.log "error: server_thread: #{$!}\n\t#{$!.backtrace.join("\n\t")}"
          $stdout.puts "--- error: server_thread: #{$!}"
          sleep 0.2
          retry unless $_CLIENT_.closed? or @game_socket.closed? or ($!.to_s =~ /invalid argument|A connection attempt failed|An existing connection was forcibly closed|An established connection was aborted by the software in your host machine./i)
        rescue
          Lich.log "error: server_thread: #{$!}\n\t#{$!.backtrace.join("\n\t")}"
          $stdout.puts "--- error: server_thread: #{$!}"
          sleep 0.2
          retry unless $_CLIENT_.closed? or @game_socket.closed? or ($!.to_s =~ /invalid argument|A connection attempt failed|An existing connection was forcibly closed|An established connection was aborted by the software in your host machine./i)
        end
      }
      @game_thread.priority = 4

      listen_for_client()
    end

    def closed?
      @game_socket.nil? or @game_socket.closed?
    end

    def name
      @xml_data.name
    end

    def register()
      return unless self.name.is_a?(String) && !self.name.empty?
      SESSIONS[self.name] = self
    end

    def dispose()
      SESSIONS.delete(self.name)
    end

    def close
      return unless @game_socket
      @game_socket.close rescue nil
      @game_thread.kill rescue nil
      @heartbeat.kill rescue nil
    end

    def _puts(str)
      @_lock.synchronize { @game_socket.puts(str) }
    end

    def puts(str)
      $_SCRIPTIDLETIMESTAMP_ = Time.now
      if script = Script.current
        script_name = script.name
      else
        script_name = '(unknown script)'
      end
      $_CLIENTBUFFER_.push "[#{script_name}]#{$SEND_CHARACTER}#{$cmd_prefix}#{str}\r\n"
      if script.nil? or not script.silent
        respond "[#{script_name}]#{$SEND_CHARACTER}#{str}\r\n"
      end
      self._puts "#{$cmd_prefix}#{str}"
      $_LASTUPSTREAM_ = "[#{script_name}]#{$SEND_CHARACTER}#{str}"
    end

    def gets
      @buffer.gets
    end

    def _gets
      @_buffer.gets
    end

    def listen_for_client()
      @client_thread = Thread.new {
        loop {
          begin
            server = TCPServer.new('127.0.0.1', @client_port)
            real_port = server.addr[1]
            sleep 0.1 while self.name.empty?
            $0 = "cabal character=%s port=%s" % [self.name, real_port]
            $stdout.write("/cabal UP %s\n" %
              {character: self.name, port: real_port}.to_json)
            $_DETACHABLE_CLIENT_ = @client_sock = SynchronizedSocket.new(server.accept)
            @client_sock.sync = true
          rescue
            Lich.log "#{$!}\n\t#{$!.backtrace.join("\n\t")}"
            server.close rescue nil
            @client_sock.close rescue nil
            @client_sock = nil
            sleep 5
            next
          ensure
            server.close rescue nil
          end
          # try again without sock
          next unless @client_sock

          begin
            $frontend = 'profanity'
            Thread.new {
              100.times { sleep 0.1; break if XMLData.indicator['IconJOINED'] }
              init_str = "<progressBar id='mana' value='0' text='mana #{XMLData.mana}/#{XMLData.max_mana}'/>"
              init_str.concat "<progressBar id='health' value='0' text='health #{XMLData.health}/#{XMLData.max_health}'/>"
              init_str.concat "<progressBar id='spirit' value='0' text='spirit #{XMLData.spirit}/#{XMLData.max_spirit}'/>"
              init_str.concat "<progressBar id='stamina' value='0' text='stamina #{XMLData.stamina}/#{XMLData.max_stamina}'/>"
              init_str.concat "<progressBar id='encumlevel' value='#{XMLData.encumbrance_value}' text='#{XMLData.encumbrance_text}'/>"
              init_str.concat "<progressBar id='pbarStance' text='stance #{XMLData.stance_text}' value='#{XMLData.stance_value}'/>"
              init_str.concat "<progressBar id='mindState' value='#{XMLData.mind_value}' text='#{XMLData.mind_text}'/>"
              init_str.concat "<spell>#{XMLData.prepared_spell}</spell>"
              init_str.concat "<right>#{GameObj.right_hand.name}</right>"
              init_str.concat "<left>#{GameObj.left_hand.name}</left>"
              for indicator in [ 'IconBLEEDING', 'IconPOISONED', 'IconDISEASED', 'IconSTANDING', 'IconKNEELING', 'IconSITTING', 'IconPRONE' ]
                init_str.concat "<indicator id='#{indicator}' visible='#{XMLData.indicator[indicator]}'/>"
              end
              for area in [ 'back', 'leftHand', 'rightHand', 'head', 'rightArm', 'abdomen', 'leftEye', 'leftArm', 'chest', 'rightLeg', 'neck', 'leftLeg', 'nsys', 'rightEye' ]
                if Wounds.send(area) > 0
                    init_str.concat "<image id=\"#{area}\" name=\"Injury#{Wounds.send(area)}\"/>"
                elsif Scars.send(area) > 0
                    init_str.concat "<image id=\"#{area}\" name=\"Scar#{Scars.send(area)}\"/>"
                end
              end
              init_str.concat '<compass>'
              shorten_dir = { 'north' => 'n', 'northeast' => 'ne', 'east' => 'e', 'southeast' => 'se', 'south' => 's', 'southwest' => 'sw', 'west' => 'w', 'northwest' => 'nw', 'up' => 'up', 'down' => 'down', 'out' => 'out' }
              for dir in XMLData.room_exits
                if short_dir = shorten_dir[dir]
                    init_str.concat "<dir value='#{short_dir}'/>"
                end
              end
              init_str.concat '</compass>'
              $_DETACHABLE_CLIENT_.puts init_str
              init_str = nil
            }
            # parse FE input
            while client_string = @client_sock.gets
              client_string = "#{$cmd_prefix}#{client_string}"
              begin
                $_IDLETIMESTAMP_ = Time.now
                Client.call(client_string, self)
              rescue
                respond "--- Lich: error: client_thread: #{$!}"
                respond $!.backtrace.first
                Lich.log "error: client_thread: #{$!}\n\t#{$!.backtrace.join("\n\t")}"
              end
            end
          rescue
            respond "--- Lich: error: client_thread: #{$!}"
            respond $!.backtrace.first
            Lich.log "error: client_thread: #{$!}\n\t#{$!.backtrace.join("\n\t")}"
          ensure
            @client_sock.close rescue nil
            @client_sock = nil
          end

          sleep 0.1
        }
      }
    end

    def handshake(key)
      #
      # send the login key
      #
      self._puts(key + "\n")
      #
      # send version string
      #
      self._puts "/FE:WIZARD /VERSION:1.0.1.22 /P:#{RUBY_PLATFORM} /XML"
      #
      # tell the server we're ready
      #
      2.times { sleep 0.3; self._puts("<c>") }
    end
  end
end
