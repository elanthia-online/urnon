require 'cabal/lich/xml-parser'
require 'cabal/script/runtime'

class Session
  SESSIONS ||= {}
  # inherit enumerable for all the goodness
  class << self
    include Enumerable
    def each()
      SESSIONS.values.each {|session| yield(session) }
    end
  end

  def self.size()
    SESSIONS.size
  end

  def self.current()
    script = Script.current
    return nil if script.nil?
    sleep 0.1 while script.session.name.empty?
    return script.session
  end

  def self.open(game_host, game_port, client_port)
    Session.new(game_host, game_port, client_port)
  end

  attr_reader :buffer, :_buffer, :xml_data,
              :game_host, :game_port,
              :game_socket, :game_thread,
              :client_thread, :client_sock, :client_port,
              :server_buffer, :client_buffer, :lock, :last_recv,
              :login_time

  def initialize(game_host, game_port, client_port)
    @lock      = Mutex.new
    @xml_data  = Cabal::XMLParser.new(self)
    @buffer    = SharedBuffer.new
    @_buffer   = SharedBuffer.new
    @_buffer.max_size = 1000

    @game_host   = game_host
    @game_port   = game_port
    @client_port = client_port

    @server_buffer = LimitedArray.new
    @server_buffer.max_size = 400
    @client_buffer = LimitedArray.new
    @client_buffer.max_size = 100
  end

  def set_socks(client: nil, game: nil)
    @client_sock = client
    @game_socket = game
  end

  def init(key)
    self.connect_to_game
    self.listen_for_client
    self.handshake(key)
  end

  def connect_to_game()
    @game_socket = TCPSocket.open(self.game_host, self.game_port)
    @game_socket.setsockopt(Socket::SOL_SOCKET, Socket::SO_KEEPALIVE, true)
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
        while incoming = @game_socket.gets
          @last_recv = Time.now
          begin
            $cmd_prefix = String.new if incoming =~ /^\034GSw/
            # The Rift, Scatter is broken...
            if incoming =~ /<compDef id='room text'><\/compDef>/
              incoming.sub!(/(.*)\s\s<compDef id='room text'><\/compDef>/)  { "<compDef id='room desc'>#{$1}</compDef>" }
            end

            if incoming =~ /<pushStream id="familiar" \/><prompt time="[0-9]+">&gt;<\/prompt>/ # Cry For Help spell is broken...
              incoming.sub!('<pushStream id="familiar" />', '')
            end
            #pp "incoming=%s" % incoming
            self.server_buffer.push(incoming)
            if alt_string = DownstreamHook.run(incoming, self)
              #pp alt_string
              if @client_sock
                begin
                  @client_sock.write(alt_string)
                rescue
                  @client_sock.close rescue nil
                  @client_sock = nil
                  respond "--- Lich: error: client_thread: #{$!}"
                  respond $!.backtrace.first
                  Lich.log "error: client_thread: #{$!}\n\t#{$!.backtrace.join("\n\t")}"
                end
              end

              alt_string = sf_to_wiz(alt_string, self) if $frontend =~ /^(?:wizard|avalon)$/
            end

            unless incoming =~ /^<settings /
              incoming.sub!('space not found', '') if incoming =~ /^<settingsInfo .*?space not found /
              begin
                REXML::Document.parse_stream(incoming, self.xml_data)
              rescue
                unless ($! || "").to_s =~ /invalid byte sequence/
                  if incoming =~ /<[^>]+='[^=>'\\]+'[^=>']+'[\s>]/
                      # Simu has a nasty habbit of bad quotes in XML.  <tag attr='this's that'>
                      incoming.gsub!(/(<[^>]+=)'([^=>'\\]+'[^=>']+)'([\s>])/) { "#{$1}\"#{$2}\"#{$3}" }
                      retry
                  end
                  $stdout.puts "--- error: server_thread: #{$!}"
                  Lich.log "error: server_thread: #{$!}\n\t#{$!.backtrace.join("\n\t")}"
                end
                self.xml_data.reset
              end
              Script.new_downstream_xml(incoming)
              stripped_server = strip_xml(incoming)
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
        retry unless @game_socket.closed? or ($!.to_s =~ /invalid argument|A connection attempt failed|An existing connection was forcibly closed|An established connection was aborted by the software in your host machine./i)
      rescue
        Lich.log "error: server_thread: #{$!}\n\t#{$!.backtrace.join("\n\t")}"
        $stdout.puts "--- error: server_thread: #{$!}"
        sleep 0.2
        retry unless @game_socket.closed? or ($!.to_s =~ /invalid argument|A connection attempt failed|An existing connection was forcibly closed|An established connection was aborted by the software in your host machine./i)
      end
    }
    @game_thread.priority = 4
  end

  def strip_xml(line)
    return line if line == "\r\n"

    if $strip_xml_multiline
        $strip_xml_multiline = $strip_xml_multiline + line
        line = $strip_xml_multiline
    end
    if (line.scan(/<pushStream[^>]*\/>/).length > line.scan(/<popStream[^>]*\/>/).length)
        $strip_xml_multiline = line
        return nil
    end
    $strip_xml_multiline = nil

    line = line.gsub(/<pushStream id=["'](?:spellfront|inv|bounty|society|speech|talk)["'][^>]*\/>.*?<popStream[^>]*>/m, '')
    line = line.gsub(/<stream id="Spells">.*?<\/stream>/m, '')
    line = line.gsub(/<(compDef|inv|component|right|left|spell|prompt)[^>]*>.*?<\/\1>/m, '')
    line = line.gsub(/<[^>]+>/, '')
    line = line.gsub('&gt;', '>')
    line = line.gsub('&lt;', '<')

    return nil if line.gsub("\n", '').gsub("\r", '').gsub(' ', '').length < 1
    return line
  end

  def closed?
    @game_socket.nil? or @game_socket.closed?
  end

  def name
    @xml_data.name
  end

  def inspect()
    "<Session:%s>" % [self.name]
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
    @lock.synchronize { @game_socket.puts(str) }
  end

  def puts(str)
    $_SCRIPTIDLETIMESTAMP_ = Time.now
    if script = Script.current
      script_name = script.name
    else
      script_name = '(unknown script)'
    end
    self.client_buffer.push "[#{script_name}]#{$SEND_CHARACTER}#{$cmd_prefix}#{str}\r\n"
    if script.nil? or not script.silent
      self.client_sock << "[#{script_name}]#{$SEND_CHARACTER}#{str}\r\n"
    end
    self._puts "#{$cmd_prefix}#{str}"
    $_LASTUPSTREAM_ = "[#{script_name}]#{$SEND_CHARACTER}#{str}"
  end

  def to_client(str)
    #pp "to_client-> %s" % str
    self.client_sock.write str
    self
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
          @client_sock = SynchronizedSocket.new(server.accept)
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
            100.times { sleep 0.1; break if self.xml_data.indicator['IconJOINED'] }
            init_str = "<progressBar id='mana' value='0' text='mana #{self.xml_data.mana}/#{self.xml_data.max_mana}'/>"
            init_str.concat "<progressBar id='health' value='0' text='health #{self.xml_data.health}/#{self.xml_data.max_health}'/>"
            init_str.concat "<progressBar id='spirit' value='0' text='spirit #{self.xml_data.spirit}/#{self.xml_data.max_spirit}'/>"
            init_str.concat "<progressBar id='stamina' value='0' text='stamina #{self.xml_data.stamina}/#{self.xml_data.max_stamina}'/>"
            init_str.concat "<progressBar id='encumlevel' value='#{self.xml_data.encumbrance_value}' text='#{self.xml_data.encumbrance_text}'/>"
            init_str.concat "<progressBar id='pbarStance' text='stance #{self.xml_data.stance_text}' value='#{self.xml_data.stance_value}'/>"
            init_str.concat "<progressBar id='mindState' value='#{self.xml_data.mind_value}' text='#{self.xml_data.mind_text}'/>"
            init_str.concat "<spell>#{self.xml_data.prepared_spell}</spell>"
            init_str.concat "<right>#{GameObj.right_hand.name}</right>"
            init_str.concat "<left>#{GameObj.left_hand.name}</left>"
            for indicator in [ 'IconBLEEDING', 'IconPOISONED', 'IconDISEASED', 'IconSTANDING', 'IconKNEELING', 'IconSITTING', 'IconPRONE' ]
              init_str.concat "<indicator id='#{indicator}' visible='#{self.xml_data.indicator[indicator]}'/>"
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
            for dir in self.xml_data.room_exits
              if short_dir = shorten_dir[dir]
                  init_str.concat "<dir value='#{short_dir}'/>"
              end
            end
            init_str.concat '</compass>'
            @client_sock.puts init_str
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
    # track when we logged in
    @login_time = Time.now
  end

  def sandbox()
    @sandbox ||= Class.new {}
  end
end
