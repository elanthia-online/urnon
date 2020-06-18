module Games
  module Gemstone
     module Game
        @@socket    = nil
        @@mutex     = Mutex.new
        @@last_recv = nil
        @@thread    = nil
        @@buffer    = SharedBuffer.new
        @@_buffer   = SharedBuffer.new
        @@_buffer.max_size = 1000
        def Game.open(host, port)
           @@socket = TCPSocket.open(host, port)
           begin
              @@socket.setsockopt(Socket::SOL_SOCKET, Socket::SO_KEEPALIVE, true)
           rescue
              Lich.log "error: #{$!}\n\t#{$!.backtrace.join("\n\t")}"
           rescue Exception
              Lich.log "error: #{$!}\n\t#{$!.backtrace.join("\n\t")}"
           end
           @@socket.sync = true
           # heart-beat check for the game socket
           Thread.new {
              @@last_recv = Time.now
              loop {
                 if (@@last_recv + 300) < Time.now
                    Lich.log "#{Time.now}: error: nothing recieved from game server in 5 minutes"
                    @@thread.kill rescue nil
                    break
                 end
                 sleep (300 - (Time.now - @@last_recv))
                 sleep 1
              }
           }
           
           @@thread = Thread.new {
              begin
                 atmospherics = false
                 while $_SERVERSTRING_ = @@socket.gets
                    @@last_recv = Time.now
                    @@_buffer.update($_SERVERSTRING_) if TESTING
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
                             REXML::Document.parse_stream($_SERVERSTRING_, XMLData)
                             # XMLData.parse($_SERVERSTRING_)
                          rescue
                             unless $!.to_s =~ /invalid byte sequence/
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
                             @@buffer.update(line) if TESTING
                             Script.new_downstream(line) unless line.empty?
                          }
                       end
                    rescue
                       $stdout.puts "--- error: server_thread: #{$!}"
                       Lich.log "error: server_thread: #{$!}\n\t#{$!.backtrace.join("\n\t")}"
                    end
                 end
              rescue Exception
                 Lich.log "error: server_thread: #{$!}\n\t#{$!.backtrace.join("\n\t")}"
                 $stdout.puts "--- error: server_thread: #{$!}"
                 sleep 0.2
                 retry unless $_CLIENT_.closed? or @@socket.closed? or ($!.to_s =~ /invalid argument|A connection attempt failed|An existing connection was forcibly closed|An established connection was aborted by the software in your host machine./i)
              rescue
                 Lich.log "error: server_thread: #{$!}\n\t#{$!.backtrace.join("\n\t")}"
                 $stdout.puts "--- error: server_thread: #{$!}"
                 sleep 0.2
                 retry unless $_CLIENT_.closed? or @@socket.closed? or ($!.to_s =~ /invalid argument|A connection attempt failed|An existing connection was forcibly closed|An established connection was aborted by the software in your host machine./i)
              end
           }
           @@thread.priority = 4
           $_SERVER_ = @@socket # deprecated
        end
        def Game.thread
           @@thread
        end
        def Game.closed?
           if @@socket.nil?
              true
           else
              @@socket.closed?
           end
        end
        def Game.close
           if @@socket
              @@socket.close rescue nil
              @@thread.kill rescue nil
           end
        end
        def Game._puts(str)
           @@mutex.synchronize {
              @@socket.puts(str)
           }
        end
        def Game.puts(str)
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
           Game._puts "#{$cmd_prefix}#{str}"
           $_LASTUPSTREAM_ = "[#{script_name}]#{$SEND_CHARACTER}#{str}"
        end
        def Game.gets
           @@buffer.gets
        end
        def Game.buffer
           @@buffer
        end
        def Game._gets
           @@_buffer.gets
        end
        def Game._buffer
           @@_buffer
        end
     end
  end
end