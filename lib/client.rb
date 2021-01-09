module Client
  def self.call(client_string)
    client_string.strip!
    if client_string == "<c>exit" or client_string == "<c>quit"
      Game.close()
      return Kernel::exit()
    end
    client_string = UpstreamHook.run(client_string)
    return nil if client_string.nil?
    if client_string =~ /^(?:<c>)?#{$lich_char}(.+)$/
      cmd = $1
      if cmd =~ /^k$|^kill$|^stop$/
          if Script.running.empty?
            respond '--- Lich: no scripts to kill'
          else
            Script.running.last.kill
          end
      elsif cmd =~ /^p$|^pause$/
          if s = Script.running.reverse.find { |s| not s.paused? }
            s.pause
          else
            respond '--- Lich: no scripts to pause'
          end
          s = nil
      elsif cmd =~ /^u$|^unpause$/
          if s = Script.running.reverse.find { |s| s.paused? }
            s.unpause
          else
            respond '--- Lich: no scripts to unpause'
          end
          s = nil
      elsif cmd =~ /^ka$|^kill\s?all$|^stop\s?all$/
          did_something = false
          Script.running.find_all { |s| not s.no_kill_all }.each { |s| s.kill; did_something = true }
          respond('--- Lich: no scripts to kill') unless did_something
      elsif cmd =~ /^pa$|^pause\s?all$/
          did_something = false
          Script.running.find_all { |s| not s.paused? and not s.no_pause_all }.each { |s| s.pause; did_something  = true }
          respond('--- Lich: no scripts to pause') unless did_something
      elsif cmd =~ /^ua$|^unpause\s?all$/
          did_something = false
          Script.running.find_all { |s| s.paused? and not s.no_pause_all }.each { |s| s.unpause; did_something = true }
          respond('--- Lich: no scripts to unpause') unless did_something
      elsif cmd =~ /^(k|kill|stop|p|pause|u|unpause)\s(.+)/
          action = $1
          target = $2
          script = (Script.running + Script.hidden)
            .find { |s|
              s.name.start_with?(target) or s.name.split("/").last.start_with?(target)
            }

          if script.nil?
            respond "--- Lich: #{target} does not appear to be running! Use ';list' or ';listall' to see what's active."
          elsif action =~ /^(?:k|kill|stop)$/
            pp "kill %s" % script.name
            pp script
            script.kill
          elsif action =~/^(?:p|pause)$/
            script.pause
          elsif action =~/^(?:u|unpause)$/
            script.unpause
          end
          action = target = script = nil
      elsif cmd =~ /^list\s?(?:all)?$|^l(?:a)?$/i
          if cmd =~ /a(?:ll)?/i
            list = Script.running + Script.hidden
          else
            list = Script.running
          end
          if list.empty?
            respond '--- Lich: no active scripts'
          else
            respond "--- Lich: #{list.collect { |s| s.paused? ? "#{s.name} (paused)" : s.name }.join(", ")}"
          end
          list = nil
      elsif cmd =~ /^force\s+[^\s]+/
          if cmd =~ /^force\s+([^\s]+)\s+(.+)$/
            Script.start($1, $2, :force => true)
          elsif cmd =~ /^force\s+([^\s]+)/
            Script.start($1, :force => true)
          end
      elsif cmd =~ /^send |^s /
          if cmd.split[1] == "to"
            script = (Script.running + Script.hidden).find { |scr| scr.name == cmd.split[2].chomp.strip } || script = (Script.running + Script.hidden).find { |scr| scr.name =~ /^#{cmd.split[2].chomp.strip}/i }
            if script
                msg = cmd.split[3..-1].join(' ').chomp
                if script.want_downstream
                  script.downstream_buffer.push(msg)
                else
                  script.unique_buffer.push(msg)
                end
                respond "--- sent to '#{script.name}': #{msg}"
            else
                respond "--- Lich: '#{cmd.split[2].chomp.strip}' does not match any active script!"
            end
            script = nil
          else
            if Script.running.empty? and Script.hidden.empty?
                respond('--- Lich: no active scripts to send to.')
            else
                msg = cmd.split[1..-1].join(' ').chomp
                respond("--- sent: #{msg}")
                Script.new_downstream(msg)
            end
          end
      elsif cmd =~ /^(?:exec|e)(q)? (.+)$/
          cmd_data = $2
          if $1.nil?
            ExecScript.start(cmd_data, flags={ :quiet => false, :trusted => true })
          else
            ExecScript.start(cmd_data, flags={ :quiet => true, :trusted => true })
          end
      elsif cmd =~ /^help$/i
          respond
          respond "Lich v#{LICH_VERSION}"
          respond
          respond 'built-in commands:'
          respond "   #{$clean_lich_char}<script name>             start a script"
          respond "   #{$clean_lich_char}force <script name>       start a script even if it's already running"
          respond "   #{$clean_lich_char}pause <script name>       pause a script"
          respond "   #{$clean_lich_char}p <script name>           ''"
          respond "   #{$clean_lich_char}unpause <script name>     unpause a script"
          respond "   #{$clean_lich_char}u <script name>           ''"
          respond "   #{$clean_lich_char}kill <script name>        kill a script"
          respond "   #{$clean_lich_char}k <script name>           ''"
          respond "   #{$clean_lich_char}pause                     pause the most recently started script that isn't aready paused"
          respond "   #{$clean_lich_char}p                         ''"
          respond "   #{$clean_lich_char}unpause                   unpause the most recently started script that is paused"
          respond "   #{$clean_lich_char}u                         ''"
          respond "   #{$clean_lich_char}kill                      kill the most recently started script"
          respond "   #{$clean_lich_char}k                         ''"
          respond "   #{$clean_lich_char}list                      show running scripts (except hidden ones)"
          respond "   #{$clean_lich_char}l                         ''"
          respond "   #{$clean_lich_char}pause all                 pause all scripts"
          respond "   #{$clean_lich_char}pa                        ''"
          respond "   #{$clean_lich_char}unpause all               unpause all scripts"
          respond "   #{$clean_lich_char}ua                        ''"
          respond "   #{$clean_lich_char}kill all                  kill all scripts"
          respond "   #{$clean_lich_char}ka                        ''"
          respond "   #{$clean_lich_char}list all                  show all running scripts"
          respond "   #{$clean_lich_char}la                        ''"
          respond
          respond "   #{$clean_lich_char}exec <code>               executes the code as if it was in a script"
          respond "   #{$clean_lich_char}e <code>                  ''"
          respond "   #{$clean_lich_char}execq <code>              same as #{$clean_lich_char}exec but without the script active and exited messages"
          respond "   #{$clean_lich_char}eq <code>                 ''"
          respond "   #{$clean_lich_char}send <line>               send a line to all scripts as if it came from the game"
          respond "   #{$clean_lich_char}send to <script> <line>   send a line to a specific script"
          respond
          respond 'If you liked this help message, you might also enjoy:'
          respond "   #{$clean_lich_char}lnet help"
          respond "   #{$clean_lich_char}magic help     (infomon must be running)"
          respond "   #{$clean_lich_char}go2 help"
          respond "   #{$clean_lich_char}repository help"
          respond "   #{$clean_lich_char}alias help"
          respond "   #{$clean_lich_char}vars help"
          respond "   #{$clean_lich_char}autostart help"
          respond
      else
          if cmd =~ /^([^\s]+)\s+(.+)/
            Script.start($1, $2)
          else
            Script.start(cmd)
          end
      end
    else
      if $offline_mode
          respond "--- Lich: offline mode: ignoring #{client_string}"
      else
          client_string = "#{$cmd_prefix}bbs" if ($frontend =~ /^(?:wizard|avalon)$/) and (client_string == "#{$cmd_prefix}\egbbk\n") # launch forum
          Game._puts client_string
      end
      $_CLIENTBUFFER_.push client_string
    end
    Script.new_upstream(client_string)
  end
end
