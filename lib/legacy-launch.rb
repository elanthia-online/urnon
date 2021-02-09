#!/usr/bin/env ruby

# First attempt at login for cabal
# prototype only

module LegacyLaunch



  def self.launch (launch_info:, front_end:)
    begin
      debug_filename = "#{TEMP_DIR}/debug-#{Time.now.strftime("%Y-%m-%d-%H-%M-%S")}.log"
      $stderr = File.open(debug_filename, 'w')
    rescue
      pp "Experienced what we call in the business a fatal error: debug-file create"
      exit
    end
    #
    # only keep the last 10 debug files
    #
    Dir.entries(TEMP_DIR).find_all { |fn| fn =~ /^debug-\d+-\d+-\d+-\d+-\d+-\d+\.log$/ }.sort.reverse[10..-1].each { |oldfile|
      begin
        File.delete("#{TEMP_DIR}/#{oldfile}")
      rescue
        Lich.log "error: #{$!}\n\t#{$!.backtrace.join("\n\t")}"
      end
    }

    custom_launch = ''
    custom_launch_dir = ''

    if front_end == "illthorn"
      launch_info["game"] = "ILLTHORN"
#      launcher_cmd = "open -n -a Illthorn \"%1\"" # when CLI enabled
    elsif front_end == "avalon"
      launch_info["game"] = "AVALON"
#      launcher_cmd = "open -n -b Avalon \"%1\""
    elsif front_end == "wizard"
      launch_info["game"] = "WIZ"
      launch_info["gamefile"] = "WIZARD.EXE"
    elsif front_end == "stormfront"
      launch_info["game"] = "STORM"
    end

    $_SERVERBUFFER_ = LimitedArray.new
    $_SERVERBUFFER_.max_size = 400
    $_CLIENTBUFFER_ = LimitedArray.new
    $_CLIENTBUFFER_.max_size = 100

    Socket.do_not_reverse_lookup = true

  main_thread = Thread.new {
    test_mode = false
    $SEND_CHARACTER = '>'
    $cmd_prefix = '<c>'
    $clean_lich_char = ';' # fixme
    $lich_char = Regexp.escape($clean_lich_char)

    #
    # open the client and have it connect to us
    # Avalon tested, Illthorn tested (FIXME: cli to pass char / port to FE)
    # Wizard and SF to be tested
    #
    if launch_info

      if launch_info[:game] =~ /ILLTHORN/i #this is going to need work
        #launcher_cmd = "open -n -a Illthorn"
        #$0 = "cabal character=%s port=%s" % [launch_info[:character], port]
        #FIXME: needs detached client workings - include in legacy-launch?
        nil
      elsif launch_info["game"] =~ /AVALON/i
        launcher_cmd = "open -n -b Avalon \"%1\""
      elsif launch_info["game"] =~ /WIZ/i
        #launcher_cmd = "start /wait launcher" #win
        nil
      eslif launch_info["game"] =~ /STORM/i
        #launcher_cmd = "start /wait launcher" #win
        nil
      end

      gamecode = launch_info["gamecode"]
      gameport = launch_info["gameport"]
      gamehost = launch_info["gamehost"]
      game     = launch_info["game"]

      if (gameport == '10121') or (gameport == '10124')
        $platinum = true
      else
        $platinum = false
      end
      Lich.log "info: gamehost: #{gamehost}"
      Lich.log "info: gameport: #{gameport}"
      Lich.log "info: game: #{game}"
      if ARGV.include?('--without-frontend')
        $_CLIENT_ = nil
      elsif $frontend == 'suks'
        nil
      else
        if game =~ /WIZ/i
          $frontend = 'wizard'
        elsif game =~ /STORM/i
          $frontend = 'stormfront'
        elsif game =~ /AVALON/i
          $frontend = 'avalon'
        else
          $frontend = 'unknown'
        end
        begin
          listener = TCPServer.new('127.0.0.1', nil)
        rescue
          $stdout.puts "--- error: cannot bind listen socket to local port: #{$!}"
          Lich.log "error: cannot bind listen socket to local port: #{$!}\n\t#{$!.backtrace.join("\n\t")}"
          exit(1)
        end
        accept_thread = Thread.new { $_CLIENT_ = SynchronizedSocket.new(listener.accept) }
        localport = listener.addr[1]
        if RUBY_PLATFORM =~ /darwin/i
          localhost = "127.0.0.1"
        else
          localhost = "localhost"
        end
        local_launch_info = launch_info
        sal_text = local_launch_info.map{|k,v| "#{k.upcase}=#{v}"}
        sal_text.collect! { |line| line.sub(/GAMEPORT=.+/, "GAMEPORT=#{localport}").sub(/GAMEHOST=.+/, "GAMEHOST=#{localhost}") }
        sal_filename = "#{TEMP_DIR}/lich#{rand(10000)}.sal"
        while File.exists?(sal_filename)
          sal_filename = "#{TEMP_DIR}/lich#{rand(10000)}.sal"
        end
        File.open(sal_filename, 'w') { |f| f.puts sal_text }
        launcher_cmd = launcher_cmd.sub('%1', sal_filename)
        launcher_cmd = launcher_cmd.tr('/', "\\") if (RUBY_PLATFORM =~ /mingw|win/i) and (RUBY_PLATFORM !~ /darwin/i)
        begin
          Lich.log "info: launcher_cmd: #{launcher_cmd}"
          system(launcher_cmd)
        rescue
          Lich.log "error: #{$!}\n\t#{$!.backtrace.join("\n\t")}"
          Lich.msgbox(:message => "error: #{$!}", :icon => :error)
        end
        Lich.log 'info: waiting for client to connect...'
        300.times { sleep 0.1; break unless accept_thread.status }
        accept_thread.kill if accept_thread.status
        Dir.chdir(LICH_DIR)
        unless $_CLIENT_
          Lich.log "error: timeout waiting for client to connect"
          listener.close rescue()
          $_CLIENT_.close rescue()
          Lich.log "info: exiting..."
          Gtk.queue { Gtk.main_quit } if defined?(Gtk)
          exit
        end
        listener.close rescue nil
        if sal_filename
          File.delete(sal_filename) rescue nil
        end
      end
      begin
        connect_thread = Thread.new {
          Game.open(gamehost, gameport)
        }
        300.times {
          sleep 0.1
          break unless connect_thread.status
        }
        if connect_thread.status
          connect_thread.kill rescue nil
          raise "error: timed out connecting to #{gamehost}:#{gameport}"
        end
      end
      Lich.log 'info: connected'
    else
      # offline mode removed
      Lich.log "error: don't know what to do"
      exit
    end

    listener = timeout_thr = nil


    # backward compatibility
    if $frontend =~ /^(?:wizard|avalon)$/
      $fake_stormfront = true
    else
      $fake_stormfront = false
    end

    if ARGV.include?('--without-frontend')
      Thread.new {
        client_thread = nil
        #
        # send the login key
        #
        Game._puts(game_key)
        game_key = nil
        #
        # send version string
        #
        client_string = "/FE:WIZARD /VERSION:1.0.1.22 /P:#{RUBY_PLATFORM} /XML"
        $_CLIENTBUFFER_.push(client_string.dup)
        Game._puts(client_string)
        #
        # tell the server we're ready
        #
        2.times {
          sleep 0.3
          $_CLIENTBUFFER_.push("<c>\r\n")
          Game._puts("<c>")
        }
        $login_time = Time.now
      }
    else
      #
      # shutdown listening socket
      #
      error_count = 0
      begin
        listener.close unless listener.closed?
      rescue
        Lich.log "warning: failed to close listener socket: #{$!}"
        if (error_count += 1) > 20
          Lich.log 'warning: giving up...'
        else
          sleep 0.05
          retry
        end
      end

      $stdout = $_CLIENT_
      $_CLIENT_.sync = true

      client_thread = Thread.new {
        $login_time = Time.now

        if $offline_mode
          nil
        elsif $frontend =~ /^(?:wizard|avalon)$/
          #
          # send the login key
          #
          client_string = $_CLIENT_.gets
          Game._puts(client_string)
          #
          # take the version string from the client, ignore it, and ask the server for xml
          #
          $_CLIENT_.gets
          client_string = "/FE:STORMFRONT /VERSION:1.0.1.26 /P:#{RUBY_PLATFORM} /XML"
          $_CLIENTBUFFER_.push(client_string.dup)
          Game._puts(client_string)
          #
          # tell the server we're ready
          #
          2.times {
            sleep 0.3
            $_CLIENTBUFFER_.push("#{$cmd_prefix}\r\n")
            Game._puts($cmd_prefix)
          }
          #
          # set up some stuff
          #
          for client_string in ["#{$cmd_prefix}_injury 2", "#{$cmd_prefix}_flag Display Inventory Boxes 1", "#{$cmd_prefix}_flag Display Dialog Boxes 0"]
            $_CLIENTBUFFER_.push(client_string)
            Game._puts(client_string)
          end
          #
          # client wants to send "GOOD", xml server won't recognize it
          #
          $_CLIENT_.gets
        else
          inv_off_proc = proc { |server_string|
            if server_string =~ /^<(?:container|clearContainer|exposeContainer)/
              server_string.gsub!(/<(?:container|clearContainer|exposeContainer)[^>]*>|<inv.+\/inv>/, '')
              if server_string.empty?
                nil
              else
                server_string
              end
            elsif server_string =~ /^<flag id="Display Inventory Boxes" status='on' desc="Display all inventory and container windows."\/>/
              server_string.sub("status='on'", "status='off'")
            elsif server_string =~ /^\s*<d cmd="flag Inventory off">Inventory<\/d>\s+ON/
              server_string.sub("flag Inventory off", "flag Inventory on").sub('ON', 'OFF')
            else
              server_string
            end
          }
          DownstreamHook.add('inventory_boxes_off', inv_off_proc)
          inv_toggle_proc = proc { |client_string|
            if client_string =~ /^(?:<c>)?_flag Display Inventory Boxes ([01])/
              if $1 == '1'
                DownstreamHook.remove('inventory_boxes_off')
                Lich.set_inventory_boxes(XMLData.player_id, true)
              else
                DownstreamHook.add('inventory_boxes_off', inv_off_proc)
                Lich.set_inventory_boxes(XMLData.player_id, false)
              end
              nil
            elsif client_string =~ /^(?:<c>)?\s*(?:set|flag)\s+inv(?:e|en|ent|ento|entor|entory)?\s+(on|off)/i
              if $1.downcase == 'on'
                DownstreamHook.remove('inventory_boxes_off')
                respond 'You have enabled viewing of inventory and container windows.'
                Lich.set_inventory_boxes(XMLData.player_id, true)
              else
                DownstreamHook.add('inventory_boxes_off', inv_off_proc)
                respond 'You have disabled viewing of inventory and container windows.'
                Lich.set_inventory_boxes(XMLData.player_id, false)
              end
              nil
            else
              client_string
            end
          }
          UpstreamHook.add('inventory_boxes_toggle', inv_toggle_proc)

          unless $offline_mode
            client_string = $_CLIENT_.gets
            Game._puts(client_string)
            client_string = $_CLIENT_.gets
            $_CLIENTBUFFER_.push(client_string.dup)
            Game._puts(client_string)
          end
        end

        begin
          while client_string = $_CLIENT_.gets
            client_string = "#{$cmd_prefix}#{client_string}" if $frontend =~ /^(?:wizard|avalon)$/
            begin
              $_IDLETIMESTAMP_ = Time.now
              do_client(client_string)
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
          sleep 0.2
          retry unless $_CLIENT_.closed? or Game.closed? or !Game.thread.alive? or ($!.to_s =~ /invalid argument|A connection attempt failed|An existing connection was forcibly closed/i)
        end
        Game.close
      }
    end

    if front_end == 'wizard'
      $link_highlight_start = "\207"
      $link_highlight_end = "\240"
      $speech_highlight_start = "\212"
      $speech_highlight_end = "\240"
    end

    client_thread.priority = 3

    $_CLIENT_.puts "\n--- Cabal v#{CABAL_VERSION} is active.  Type #{$clean_lich_char}help for usage info.\n\n"

    Game.thread.join
    client_thread.kill rescue nil

}

  end
end
