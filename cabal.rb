# encoding: US-ASCII
#####
# Copyright (C) 2005-2006 Murray Miron
# All rights reserved.
#
# Redistribution and use in source and binary forms, with or without
# modification, are permitted provided that the following conditions
# are met:
#
#   Redistributions of source code must retain the above copyright
# notice, this list of conditions and the following disclaimer.
#
#   Redistributions in binary form must reproduce the above copyright
# notice, this list of conditions and the following disclaimer in the
# documentation and/or other materials provided with the distribution.
#
#   Neither the name of the organization nor the names of its contributors
# may be used to endorse or promote products derived from this software
# without specific prior written permission.
#
# THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS
# "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT
# LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR
# A PARTICULAR PURPOSE ARE DISCLAIMED.  IN NO EVENT SHALL THE COPYRIGHT OWNER OR
# CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL,
# EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO,
# PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR
# PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF
# LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING
# NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS
# SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
#####

#
# Lich is maintained by Matt Lowe (tillmen@lichproject.org)
#

require "benchmark"

LICH_VERSION = '4.6.50'
TESTING = false
$VERBOSE = nil

require 'time'
require 'socket'
require 'rexml/document'
require 'rexml/streamlistener'
require 'stringio'
require 'zlib'
require 'drb'
require 'resolv'
require 'digest/md5'
require 'sqlite3'
require 'gtk2'
HAVE_GTK = true

begin
   # stupid workaround for Windows
   # seems to avoid a 10 second lag when starting lnet, without adding a 10 second lag at startup
   require 'openssl'
   OpenSSL::PKey::RSA.new(512)
rescue LoadError
   nil # not required for basic Lich; however, lnet and repository scripts will fail without openssl
rescue
   nil
end

if defined?(Gtk)
   module Gtk
      # Calling Gtk API in a thread other than the main thread may cause random segfaults
      def Gtk.queue &block
         GLib::Timeout.add(1) {
            begin
               block.call
            rescue
               respond "error in Gtk.queue: #{$!}"
               Lich.log "error in Gtk.queue: #{$!}\n\t#{$!.backtrace.join("\n\t")}"
            rescue SyntaxError
               respond "error in Gtk.queue: #{$!}"
               Lich.log "error in Gtk.queue: #{$!}\n\t#{$!.backtrace.join("\n\t")}"
            rescue SystemExit
               nil
            rescue SecurityError
               respond "error in Gtk.queue: #{$!}"
               Lich.log "error in Gtk.queue: #{$!}\n\t#{$!.backtrace.join("\n\t")}"
            rescue ThreadError
               respond "error in Gtk.queue: #{$!}"
               Lich.log "error in Gtk.queue: #{$!}\n\t#{$!.backtrace.join("\n\t")}"
            rescue SystemStackError
               respond "error in Gtk.queue: #{$!}"
               Lich.log "error in Gtk.queue: #{$!}\n\t#{$!.backtrace.join("\n\t")}"
            rescue Exception
               respond "error in Gtk.queue: #{$!}"
               Lich.log "error in Gtk.queue: #{$!}\n\t#{$!.backtrace.join("\n\t")}"
            rescue ScriptError
               respond "error in Gtk.queue: #{$!}"
               Lich.log "error in Gtk.queue: #{$!}\n\t#{$!.backtrace.join("\n\t")}"
            rescue LoadError
               respond "error in Gtk.queue: #{$!}"
               Lich.log "error in Gtk.queue: #{$!}\n\t#{$!.backtrace.join("\n\t")}"
            rescue NoMemoryError
               respond "error in Gtk.queue: #{$!}"
               Lich.log "error in Gtk.queue: #{$!}\n\t#{$!.backtrace.join("\n\t")}"
            rescue
               respond "error in Gtk.queue: #{$!}"
               Lich.log "error in Gtk.queue: #{$!}\n\t#{$!.backtrace.join("\n\t")}"
            end
            false # don't repeat timeout
         }
      end
   end
end

module Lich
   @@hosts_file = nil
   @@lich_db    = nil
   def Lich.db
      if $SAFE == 0
         @@lich_db ||= SQLite3::Database.new("#{DATA_DIR}/lich.db3")
      else
         nil
      end
   end
   def Lich.init_db
      begin
         Lich.db.execute("CREATE TABLE IF NOT EXISTS script_setting (script TEXT NOT NULL, name TEXT NOT NULL, value BLOB, PRIMARY KEY(script, name));")
         Lich.db.execute("CREATE TABLE IF NOT EXISTS script_auto_settings (script TEXT NOT NULL, scope TEXT, hash BLOB, PRIMARY KEY(script, scope));")
         Lich.db.execute("CREATE TABLE IF NOT EXISTS lich_settings (name TEXT NOT NULL, value TEXT, PRIMARY KEY(name));")
         Lich.db.execute("CREATE TABLE IF NOT EXISTS uservars (scope TEXT NOT NULL, hash BLOB, PRIMARY KEY(scope));")
         if (RUBY_VERSION =~ /^2\.[012]\./)
            Lich.db.execute("CREATE TABLE IF NOT EXISTS trusted_scripts (name TEXT NOT NULL);")
         end
         Lich.db.execute("CREATE TABLE IF NOT EXISTS simu_game_entry (character TEXT NOT NULL, game_code TEXT NOT NULL, data BLOB, PRIMARY KEY(character, game_code));")
         Lich.db.execute("CREATE TABLE IF NOT EXISTS enable_inventory_boxes (player_id INTEGER NOT NULL, PRIMARY KEY(player_id));")
      rescue SQLite3::BusyException
         sleep 0.1
         retry
      end
   end
   def Lich.class_variable_get(*a); nil; end
   def Lich.class_eval(*a);         nil; end
   def Lich.module_eval(*a);        nil; end
   def Lich.log(msg)
      $stderr.puts "#{Time.now.strftime("%Y-%m-%d %H:%M:%S")}: #{msg}"
   end
   def Lich.msgbox(args)
      if defined?(Win32)
         if args[:buttons] == :ok_cancel
            buttons = Win32::MB_OKCANCEL
         elsif args[:buttons] == :yes_no
            buttons = Win32::MB_YESNO
         else
            buttons = Win32::MB_OK
         end
         if args[:icon] == :error
            icon = Win32::MB_ICONERROR
         elsif args[:icon] == :question
            icon = Win32::MB_ICONQUESTION
         elsif args[:icon] == :warning
            icon = Win32::MB_ICONWARNING
         else
            icon = 0
         end
         args[:title] ||= "Lich v#{LICH_VERSION}"
         r = Win32.MessageBox(:lpText => args[:message], :lpCaption => args[:title], :uType => (buttons|icon))
         if r == Win32::IDIOK
            return :ok
         elsif r == Win32::IDICANCEL
            return :cancel
         elsif r == Win32::IDIYES
            return :yes
         elsif r == Win32::IDINO
            return :no
         else
            return nil
         end
      elsif defined?(Gtk)
         if args[:buttons] == :ok_cancel
            buttons = Gtk::MessageDialog::BUTTONS_OK_CANCEL
         elsif args[:buttons] == :yes_no
            buttons = Gtk::MessageDialog::BUTTONS_YES_NO
         else
            buttons = Gtk::MessageDialog::BUTTONS_OK
         end
         if args[:icon] == :error
            type = Gtk::MessageDialog::ERROR
         elsif args[:icon] == :question
            type = Gtk::MessageDialog::QUESTION
         elsif args[:icon] == :warning
            type = Gtk::MessageDialog::WARNING
         else
            type = Gtk::MessageDialog::INFO
         end
         dialog = Gtk::MessageDialog.new(nil, Gtk::Dialog::MODAL, type, buttons, args[:message])
         args[:title] ||= "Lich v#{LICH_VERSION}"
         dialog.title = args[:title]
         response = nil
         dialog.run { |r|
            response = r
            dialog.destroy
         }
         if response == Gtk::Dialog::RESPONSE_OK
            return :ok
         elsif response == Gtk::Dialog::RESPONSE_CANCEL
            return :cancel
         elsif response == Gtk::Dialog::RESPONSE_YES
            return :yes
         elsif response == Gtk::Dialog::RESPONSE_NO
            return :no
         else
            return nil
         end
      elsif $stdout.isatty
         $stdout.puts(args[:message])
         return nil
      end
   end
   def Lich.get_simu_launcher
      if defined?(Win32)
         begin
            launcher_key = Win32.RegOpenKeyEx(:hKey => Win32::HKEY_LOCAL_MACHINE, :lpSubKey => 'Software\\Classes\\Simutronics.Autolaunch\\Shell\\Open\\command', :samDesired => (Win32::KEY_ALL_ACCESS|Win32::KEY_WOW64_32KEY))[:phkResult]
            launcher_cmd = Win32.RegQueryValueEx(:hKey => launcher_key, :lpValueName => 'RealCommand')[:lpData]
            if launcher_cmd.nil? or launcher_cmd.empty?
               launcher_cmd = Win32.RegQueryValueEx(:hKey => launcher_key)[:lpData]
            end
            return launcher_cmd
         ensure
            Win32.RegCloseKey(:hKey => launcher_key) rescue nil
         end
      elsif defined?(Wine)
         launcher_cmd = Wine.registry_gets('HKEY_LOCAL_MACHINE\\Software\\Classes\\Simutronics.Autolaunch\\Shell\\Open\\command\\RealCommand')
         unless launcher_cmd and not launcher_cmd.empty?
            launcher_cmd = Wine.registry_gets('HKEY_LOCAL_MACHINE\\Software\\Classes\\Simutronics.Autolaunch\\Shell\\Open\\command\\')
         end
         return launcher_cmd
      else
         return nil
      end
   end
   def Lich.link_to_sge
      if defined?(Win32)
         if Win32.admin?
            begin
               launcher_key = Win32.RegOpenKeyEx(:hKey => Win32::HKEY_LOCAL_MACHINE, :lpSubKey => 'Software\\Simutronics\\Launcher', :samDesired => (Win32::KEY_ALL_ACCESS|Win32::KEY_WOW64_32KEY))[:phkResult]
               r = Win32.RegQueryValueEx(:hKey => launcher_key, :lpValueName => 'RealDirectory')
               if (r[:return] == 0) and not r[:lpData].empty?
                  # already linked
                  return true
               end
               r = Win32.GetModuleFileName
               unless r[:return] > 0
                  # fixme
                  return false
               end
               new_launcher_dir = "\"#{r[:lpFilename]}\" \"#{File.expand_path($PROGRAM_NAME)}\" "
               r = Win32.RegQueryValueEx(:hKey => launcher_key, :lpValueName => 'Directory')
               launcher_dir = r[:lpData]
               r = Win32.RegSetValueEx(:hKey => launcher_key, :lpValueName => 'RealDirectory', :dwType => Win32::REG_SZ, :lpData => launcher_dir)
               return false unless (r == 0)
               r = Win32.RegSetValueEx(:hKey => launcher_key, :lpValueName => 'Directory', :dwType => Win32::REG_SZ, :lpData => new_launcher_dir)
               return (r == 0)
            ensure
               Win32.RegCloseKey(:hKey => launcher_key) rescue nil
            end
         else
            begin
               r = Win32.GetModuleFileName
               file = ((r[:return] > 0) ? r[:lpFilename] : 'rubyw.exe')
               params = "#{$PROGRAM_NAME.split(/\/|\\/).last} --link-to-sge"
               r = Win32.ShellExecuteEx(:lpVerb => 'runas', :lpFile => file, :lpDirectory => LICH_DIR.tr("/", "\\"), :lpParameters => params, :fMask => Win32::SEE_MASK_NOCLOSEPROCESS)
               if r[:return] > 0
                  process_id = r[:hProcess]
                  sleep 0.2 while Win32.GetExitCodeProcess(:hProcess => process_id)[:lpExitCode] == Win32::STILL_ACTIVE
                  sleep 3
               else
                  Win32.ShellExecute(:lpOperation => 'runas', :lpFile => file, :lpDirectory => LICH_DIR.tr("/", "\\"), :lpParameters => params)
                  sleep 6
               end
            rescue
               Lich.msgbox(:message => $!)
            end
         end
      elsif defined?(Wine)
         launch_dir = Wine.registry_gets('HKEY_LOCAL_MACHINE\\Software\\Simutronics\\Launcher\\Directory')
         return false unless launch_dir
         lich_launch_dir = "#{File.expand_path($PROGRAM_NAME)} --wine=#{Wine::BIN} --wine-prefix=#{Wine::PREFIX}  "
         result = true
         if launch_dir
            if launch_dir =~ /lich/i
               $stdout.puts "--- warning: Lich appears to already be installed to the registry"
               Lich.log "warning: Lich appears to already be installed to the registry"
               Lich.log 'info: launch_dir: ' + launch_dir
            else
               result = result && Wine.registry_puts('HKEY_LOCAL_MACHINE\\Software\\Simutronics\\Launcher\\RealDirectory', launch_dir)
               result = result && Wine.registry_puts('HKEY_LOCAL_MACHINE\\Software\\Simutronics\\Launcher\\Directory', lich_launch_dir)
            end
         end
         return result
      else
         return false
      end
   end
   def Lich.unlink_from_sge
      if defined?(Win32)
         if Win32.admin?
            begin
               launcher_key = Win32.RegOpenKeyEx(:hKey => Win32::HKEY_LOCAL_MACHINE, :lpSubKey => 'Software\\Simutronics\\Launcher', :samDesired => (Win32::KEY_ALL_ACCESS|Win32::KEY_WOW64_32KEY))[:phkResult]
               real_directory = Win32.RegQueryValueEx(:hKey => launcher_key, :lpValueName => 'RealDirectory')[:lpData]
               if real_directory.nil? or real_directory.empty?
                  # not linked
                  return true
               end
               r = Win32.RegSetValueEx(:hKey => launcher_key, :lpValueName => 'Directory', :dwType => Win32::REG_SZ, :lpData => real_directory)
               return false unless (r == 0)
               r = Win32.RegDeleteValue(:hKey => launcher_key, :lpValueName => 'RealDirectory')
               return (r == 0)
            ensure
               Win32.RegCloseKey(:hKey => launcher_key) rescue nil
            end
         else
            begin
               r = Win32.GetModuleFileName
               file = ((r[:return] > 0) ? r[:lpFilename] : 'rubyw.exe')
               params = "#{$PROGRAM_NAME.split(/\/|\\/).last} --unlink-from-sge"
               r = Win32.ShellExecuteEx(:lpVerb => 'runas', :lpFile => file, :lpDirectory => LICH_DIR.tr("/", "\\"), :lpParameters => params, :fMask => Win32::SEE_MASK_NOCLOSEPROCESS)
               if r[:return] > 0
                  process_id = r[:hProcess]
                  sleep 0.2 while Win32.GetExitCodeProcess(:hProcess => process_id)[:lpExitCode] == Win32::STILL_ACTIVE
                  sleep 3
               else
                  Win32.ShellExecute(:lpOperation => 'runas', :lpFile => file, :lpDirectory => LICH_DIR.tr("/", "\\"), :lpParameters => params)
                  sleep 6
               end
            rescue
               Lich.msgbox(:message => $!)
            end
         end
      elsif defined?(Wine)
         real_launch_dir = Wine.registry_gets('HKEY_LOCAL_MACHINE\\Software\\Simutronics\\Launcher\\RealDirectory')
         result = true
         if real_launch_dir and not real_launch_dir.empty?
            result = result && Wine.registry_puts('HKEY_LOCAL_MACHINE\\Software\\Simutronics\\Launcher\\Directory', real_launch_dir)
            result = result && Wine.registry_puts('HKEY_LOCAL_MACHINE\\Software\\Simutronics\\Launcher\\RealDirectory', '')
         end
         return result
      else
         return false
      end
   end
   def Lich.link_to_sal
      if defined?(Win32)
         if Win32.admin?
            begin
               # fixme: 64 bit browsers?
               launcher_key = Win32.RegOpenKeyEx(:hKey => Win32::HKEY_LOCAL_MACHINE, :lpSubKey => 'Software\\Classes\\Simutronics.Autolaunch\\Shell\\Open\\command', :samDesired => (Win32::KEY_ALL_ACCESS|Win32::KEY_WOW64_32KEY))[:phkResult]
               r = Win32.RegQueryValueEx(:hKey => launcher_key, :lpValueName => 'RealCommand')
               if (r[:return] == 0) and not r[:lpData].empty?
                  # already linked
                  return true
               end
               r = Win32.GetModuleFileName
               unless r[:return] > 0
                  # fixme
                  return false
               end
               new_launcher_cmd = "\"#{r[:lpFilename]}\" \"#{File.expand_path($PROGRAM_NAME)}\" %1"
               r = Win32.RegQueryValueEx(:hKey => launcher_key)
               launcher_cmd = r[:lpData]
               r = Win32.RegSetValueEx(:hKey => launcher_key, :lpValueName => 'RealCommand', :dwType => Win32::REG_SZ, :lpData => launcher_cmd)
               return false unless (r == 0)
               r = Win32.RegSetValueEx(:hKey => launcher_key, :dwType => Win32::REG_SZ, :lpData => new_launcher_cmd)
               return (r == 0)
            ensure
               Win32.RegCloseKey(:hKey => launcher_key) rescue nil
            end
         else
            begin
               r = Win32.GetModuleFileName
               file = ((r[:return] > 0) ? r[:lpFilename] : 'rubyw.exe')
               params = "#{$PROGRAM_NAME.split(/\/|\\/).last} --link-to-sal"
               r = Win32.ShellExecuteEx(:lpVerb => 'runas', :lpFile => file, :lpDirectory => LICH_DIR.tr("/", "\\"), :lpParameters => params, :fMask => Win32::SEE_MASK_NOCLOSEPROCESS)
               if r[:return] > 0
                  process_id = r[:hProcess]
                  sleep 0.2 while Win32.GetExitCodeProcess(:hProcess => process_id)[:lpExitCode] == Win32::STILL_ACTIVE
                  sleep 3
               else
                  Win32.ShellExecute(:lpOperation => 'runas', :lpFile => file, :lpDirectory => LICH_DIR.tr("/", "\\"), :lpParameters => params)
                  sleep 6
               end
            rescue
               Lich.msgbox(:message => $!)
            end
         end
      elsif defined?(Wine)
         launch_cmd = Wine.registry_gets('HKEY_LOCAL_MACHINE\\Software\\Classes\\Simutronics.Autolaunch\\Shell\\Open\\command\\')
         return false unless launch_cmd
         new_launch_cmd = "#{File.expand_path($PROGRAM_NAME)} --wine=#{Wine::BIN} --wine-prefix=#{Wine::PREFIX} %1"
         result = true
         if launch_cmd
            if launch_cmd =~ /lich/i
               $stdout.puts "--- warning: Lich appears to already be installed to the registry"
               Lich.log "warning: Lich appears to already be installed to the registry"
               Lich.log 'info: launch_cmd: ' + launch_cmd
            else
               result = result && Wine.registry_puts('HKEY_LOCAL_MACHINE\\Software\\Classes\\Simutronics.Autolaunch\\Shell\\Open\\command\\RealCommand', launch_cmd)
               result = result && Wine.registry_puts('HKEY_LOCAL_MACHINE\\Software\\Classes\\Simutronics.Autolaunch\\Shell\\Open\\command\\', new_launch_cmd)
            end
         end
         return result
      else
         return false
      end
   end
   def Lich.unlink_from_sal
      if defined?(Win32)
         if Win32.admin?
            begin
               launcher_key = Win32.RegOpenKeyEx(:hKey => Win32::HKEY_LOCAL_MACHINE, :lpSubKey => 'Software\\Classes\\Simutronics.Autolaunch\\Shell\\Open\\command', :samDesired => (Win32::KEY_ALL_ACCESS|Win32::KEY_WOW64_32KEY))[:phkResult]
               real_directory = Win32.RegQueryValueEx(:hKey => launcher_key, :lpValueName => 'RealCommand')[:lpData]
               if real_directory.nil? or real_directory.empty?
                  # not linked
                  return true
               end
               r = Win32.RegSetValueEx(:hKey => launcher_key, :dwType => Win32::REG_SZ, :lpData => real_directory)
               return false unless (r == 0)
               r = Win32.RegDeleteValue(:hKey => launcher_key, :lpValueName => 'RealCommand')
               return (r == 0)
            ensure
               Win32.RegCloseKey(:hKey => launcher_key) rescue nil
            end
         else
            begin
               r = Win32.GetModuleFileName
               file = ((r[:return] > 0) ? r[:lpFilename] : 'rubyw.exe')
               params = "#{$PROGRAM_NAME.split(/\/|\\/).last} --unlink-from-sal"
               r = Win32.ShellExecuteEx(:lpVerb => 'runas', :lpFile => file, :lpDirectory => LICH_DIR.tr("/", "\\"), :lpParameters => params, :fMask => Win32::SEE_MASK_NOCLOSEPROCESS)
               if r[:return] > 0
                  process_id = r[:hProcess]
                  sleep 0.2 while Win32.GetExitCodeProcess(:hProcess => process_id)[:lpExitCode] == Win32::STILL_ACTIVE
                  sleep 3
               else
                  Win32.ShellExecute(:lpOperation => 'runas', :lpFile => file, :lpDirectory => LICH_DIR.tr("/", "\\"), :lpParameters => params)
                  sleep 6
               end
            rescue
               Lich.msgbox(:message => $!)
            end
         end
      elsif defined?(Wine)
         real_launch_cmd = Wine.registry_gets('HKEY_LOCAL_MACHINE\\Software\\Classes\\Simutronics.Autolaunch\\Shell\\Open\\command\\RealCommand')
         result = true
         if real_launch_cmd and not real_launch_cmd.empty?
            result = result && Wine.registry_puts('HKEY_LOCAL_MACHINE\\Software\\Classes\\Simutronics.Autolaunch\\Shell\\Open\\command\\', real_launch_cmd)
            result = result && Wine.registry_puts('HKEY_LOCAL_MACHINE\\Software\\Classes\\Simutronics.Autolaunch\\Shell\\Open\\command\\RealCommand', '')
         end
         return result
      else
         return false
      end
   end
   def Lich.hosts_file
      Lich.find_hosts_file if @@hosts_file.nil?
      return @@hosts_file
   end
   def Lich.find_hosts_file
      if defined?(Win32)
         begin
            key = Win32.RegOpenKeyEx(:hKey => Win32::HKEY_LOCAL_MACHINE, :lpSubKey => 'System\\CurrentControlSet\\Services\\Tcpip\\Parameters', :samDesired => Win32::KEY_READ)[:phkResult]
            hosts_path = Win32.RegQueryValueEx(:hKey => key, :lpValueName => 'DataBasePath')[:lpData]
         ensure
            Win32.RegCloseKey(:hKey => key) rescue nil
         end
         if hosts_path
            windir = (ENV['windir'] || ENV['SYSTEMROOT'] || 'c:\windows')
            hosts_path.gsub('%SystemRoot%', windir)
            hosts_file = "#{hosts_path}\\hosts"
            if File.exists?(hosts_file)
               return (@@hosts_file = hosts_file)
            end
         end
         if (windir = (ENV['windir'] || ENV['SYSTEMROOT'])) and File.exists?("#{windir}\\system32\\drivers\\etc\\hosts")
            return (@@hosts_file = "#{windir}\\system32\\drivers\\etc\\hosts")
         end
         for drive in ['C','D','E','F','G','H','I','J','K','L','M','N','O','P','Q','R','S','T','U','V','W','X','Y','Z']
            for windir in ['winnt','windows']
               if File.exists?("#{drive}:\\#{windir}\\system32\\drivers\\etc\\hosts")
                  return (@@hosts_file = "#{drive}:\\#{windir}\\system32\\drivers\\etc\\hosts")
               end
            end
         end
      else # Linux/Mac
         if File.exists?('/etc/hosts')
            return (@@hosts_file = '/etc/hosts')
         elsif File.exists?('/private/etc/hosts')
            return (@@hosts_file = '/private/etc/hosts')
         end
      end
      return (@@hosts_file = false)
   end
   def Lich.modify_hosts(game_host)
      if Lich.hosts_file and File.exists?(Lich.hosts_file)
         at_exit { Lich.restore_hosts }
         Lich.restore_hosts
         if File.exists?("#{Lich.hosts_file}.bak")
            return false
         end
         begin
            # copy hosts to hosts.bak
            File.open("#{Lich.hosts_file}.bak", 'w') { |hb| File.open(Lich.hosts_file) { |h| hb.write(h.read) } }
         rescue
            File.unlink("#{Lich.hosts_file}.bak") if File.exists?("#{Lich.hosts_file}.bak")
            return false
         end
         File.open(Lich.hosts_file, 'a') { |f| f.write "\r\n127.0.0.1\t\t#{game_host}" }
         return true
      else
         return false
      end
   end
   def Lich.restore_hosts
      if Lich.hosts_file and File.exists?(Lich.hosts_file)      
         begin
            # fixme: use rename instead?  test rename on windows
            if File.exists?("#{Lich.hosts_file}.bak")
               File.open("#{Lich.hosts_file}.bak") { |infile|
                  File.open(Lich.hosts_file, 'w') { |outfile|
                     outfile.write(infile.read)
                  }
               }
               File.unlink "#{Lich.hosts_file}.bak"
            end
         rescue
            $stdout.puts "--- error: restore_hosts: #{$!}"
            Lich.log "error: restore_hosts: #{$!}\n\t#{$!.backtrace.join("\n\t")}"
            exit(1)
         end
      end
   end
   def Lich.inventory_boxes(player_id)
      begin
         v = Lich.db.get_first_value('SELECT player_id FROM enable_inventory_boxes WHERE player_id=?;', player_id.to_i)
      rescue SQLite3::BusyException
         sleep 0.1
         retry
      end
      if v
         true
      else
         false
      end
   end
   def Lich.set_inventory_boxes(player_id, enabled)
      if enabled
         begin
            Lich.db.execute('INSERT OR REPLACE INTO enable_inventory_boxes values(?);', player_id.to_i)
         rescue SQLite3::BusyException
            sleep 0.1
            retry
         end
      else
         begin
            Lich.db.execute('DELETE FROM enable_inventory_boxes where player_id=?;', player_id.to_i)
         rescue SQLite3::BusyException
            sleep 0.1
            retry
         end
      end
      nil
   end
   def Lich.win32_launch_method
      begin
         val = Lich.db.get_first_value("SELECT value FROM lich_settings WHERE name='win32_launch_method';")
      rescue SQLite3::BusyException
         sleep 0.1
         retry
      end
      val
   end
   def Lich.win32_launch_method=(val)
      begin
         Lich.db.execute("INSERT OR REPLACE INTO lich_settings(name,value) values('win32_launch_method',?);", val.to_s.encode('UTF-8'))
      rescue SQLite3::BusyException
         sleep 0.1
         retry
      end
      nil
   end
   def Lich.fix_game_host_port(gamehost,gameport)
      if (gamehost == 'gs-plat.simutronics.net') and (gameport.to_i == 10121)
         gamehost = 'storm.gs4.game.play.net'
         gameport = 10124
      elsif (gamehost == 'gs3.simutronics.net') and (gameport.to_i == 4900)
         gamehost = 'storm.gs4.game.play.net'
         gameport = 10024
      elsif (gamehost == 'gs4.simutronics.net') and (gameport.to_i == 10321)
         game_host = 'storm.gs4.game.play.net'
         game_port = 10324
      elsif (gamehost == 'prime.dr.game.play.net') and (gameport.to_i == 4901)
         gamehost = 'dr.simutronics.net'
         gameport = 11024
      end
      [ gamehost, gameport ]
   end
   def Lich.break_game_host_port(gamehost,gameport)
      if (gamehost == 'storm.gs4.game.play.net') and (gameport.to_i == 10324)
         gamehost = 'gs4.simutronics.net'
         gameport = 10321
      elsif (gamehost == 'storm.gs4.game.play.net') and (gameport.to_i == 10124)
         gamehost = 'gs-plat.simutronics.net'
         gameport = 10121
      elsif (gamehost == 'storm.gs4.game.play.net') and (gameport.to_i == 10024)
         gamehost = 'gs3.simutronics.net'
         gameport = 4900
      elsif (gamehost == 'storm.gs4.game.play.net') and (gameport.to_i == 10324)
         game_host = 'gs4.simutronics.net'
         game_port = 10321
      elsif (gamehost == 'dr.simutronics.net') and (gameport.to_i == 11024)
         gamehost = 'prime.dr.game.play.net'
         gameport = 4901
      end
      [ gamehost, gameport ]
   end
end

class NilClass
   def dup
      nil
   end
   def method_missing(*args)
      nil
   end
   def split(*val)
      Array.new
   end
   def to_s
      ""
   end
   def strip
      ""
   end
   def +(val)
      val
   end
   def closed?
      true
   end
end

class Numeric
   def as_time
      sprintf("%d:%02d:%02d", (self / 60).truncate, self.truncate % 60, ((self % 1) * 60).truncate)
   end
   def with_commas
      self.to_s.reverse.scan(/(?:\d*\.)?\d{1,3}-?/).join(',').reverse
   end
end

class TrueClass
   def method_missing(*usersave)
      true
   end
end

class FalseClass
   def method_missing(*usersave)
      nil
   end
end

class String
   @@elevated_untaint = proc { |what| what.orig_untaint }
   alias :orig_untaint :untaint
   def untaint
      @@elevated_untaint.call(self)
   end
   def to_s
      self.dup
   end
   def stream
      @stream
   end
   def stream=(val)
      @stream ||= val
   end
end

class StringProc
   def initialize(string)
      @string = string
      @string.untaint
   end
   def kind_of?(type)
      Proc.new {}.kind_of? type
   end
   def class
      Proc
   end
   def call(*a)
      proc { begin; $SAFE = 3; rescue; nil; end; eval(@string) }.call
   end
   def _dump(d=nil)
      @string
   end
   def inspect
      "StringProc.new(#{@string.inspect})"
   end
end

class SynchronizedSocket
   def initialize(o)
      @delegate = o
      @mutex = Mutex.new
      self
   end
   def puts(*args, &block)
      @mutex.synchronize {
         @delegate.puts *args, &block
      }
   end
   def write(*args, &block)
      @mutex.synchronize {
         @delegate.write *args, &block
      }
   end
   def method_missing(method, *args, &block)
      @delegate.__send__ method, *args, &block
   end
end

class LimitedArray < Array
   attr_accessor :max_size
   def initialize(size=0, obj=nil)
      @max_size = 200
      super
   end
   def push(line)
      self.shift while self.length >= @max_size
      super
   end
   def shove(line)
      push(line)
   end
   def history
      Array.new
   end
end

class XMLParser
   attr_reader :mana, :max_mana, :health, :max_health, :spirit, :max_spirit, :last_spirit, :stamina, :max_stamina, :stance_text, :stance_value, :mind_text, :mind_value, :prepared_spell, :encumbrance_text, :encumbrance_full_text, :encumbrance_value, :indicator, :injuries, :injury_mode, :room_count, :room_title, :room_description, :room_exits, :room_exits_string, :familiar_room_title, :familiar_room_description, :familiar_room_exits, :bounty_task, :injury_mode, :server_time, :server_time_offset, :roundtime_end, :cast_roundtime_end, :last_pulse, :level, :next_level_value, :next_level_text, :society_task, :stow_container_id, :name, :game, :in_stream, :player_id, :active_spells, :prompt, :current_target_ids, :current_target_id, :room_window_disabled
   attr_accessor :send_fake_tags

   @@warned_deprecated_spellfront = 0

   include REXML::StreamListener

   def initialize
      @buffer = String.new
      @unescape = { 'lt' => '<', 'gt' => '>', 'quot' => '"', 'apos' => "'", 'amp' => '&' }
      @bold = false
      @active_tags = Array.new
      @active_ids = Array.new
      @last_tag = String.new
      @last_id = String.new
      @current_stream = String.new
      @current_style = String.new
      @stow_container_id = nil
      @obj_location = nil
      @obj_exist = nil
      @obj_noun = nil
      @obj_before_name = nil
      @obj_name = nil
      @obj_after_name = nil
      @pc = nil
      @last_obj = nil
      @in_stream = false
      @player_status = nil
      @fam_mode = String.new
      @room_window_disabled = false
      @wound_gsl = String.new
      @scar_gsl = String.new
      @send_fake_tags = false
      @prompt = String.new
      @nerve_tracker_num = 0
      @nerve_tracker_active = 'no'
      @server_time = Time.now.to_i
      @server_time_offset = 0
      @roundtime_end = 0
      @cast_roundtime_end = 0
      @last_pulse = Time.now.to_i
      @level = 0
      @next_level_value = 0
      @next_level_text = String.new
      @current_target_ids = Array.new

      @room_count = 0
      @room_title = String.new
      @room_description = String.new
      @room_exits = Array.new
      @room_exits_string = String.new

      @familiar_room_title = String.new
      @familiar_room_description = String.new
      @familiar_room_exits = Array.new

      @bounty_task = String.new
      @society_task = String.new

      @name = String.new
      @game = String.new
      @player_id = String.new
      @mana = 0
      @max_mana = 0
      @health = 0
      @max_health = 0
      @spirit = 0
      @max_spirit = 0
      @last_spirit = nil
      @stamina = 0
      @max_stamina = 0
      @stance_text = String.new
      @stance_value = 0
      @mind_text = String.new
      @mind_value = 0
      @prepared_spell = 'None'
      @encumbrance_text = String.new
      @encumbrance_full_text = String.new
      @encumbrance_value = 0
      @indicator = Hash.new
      @injuries = {'back' => {'scar' => 0, 'wound' => 0}, 'leftHand' => {'scar' => 0, 'wound' => 0}, 'rightHand' => {'scar' => 0, 'wound' => 0}, 'head' => {'scar' => 0, 'wound' => 0}, 'rightArm' => {'scar' => 0, 'wound' => 0}, 'abdomen' => {'scar' => 0, 'wound' => 0}, 'leftEye' => {'scar' => 0, 'wound' => 0}, 'leftArm' => {'scar' => 0, 'wound' => 0}, 'chest' => {'scar' => 0, 'wound' => 0}, 'leftFoot' => {'scar' => 0, 'wound' => 0}, 'rightFoot' => {'scar' => 0, 'wound' => 0}, 'rightLeg' => {'scar' => 0, 'wound' => 0}, 'neck' => {'scar' => 0, 'wound' => 0}, 'leftLeg' => {'scar' => 0, 'wound' => 0}, 'nsys' => {'scar' => 0, 'wound' => 0}, 'rightEye' => {'scar' => 0, 'wound' => 0}}
      @injury_mode = 0

      @active_spells = Hash.new

   end

   def reset
      @active_tags = Array.new
      @active_ids = Array.new
      @current_stream = String.new
      @current_style = String.new
   end

   def make_wound_gsl
      @wound_gsl = sprintf("0b0%02b%02b%02b%02b%02b%02b%02b%02b%02b%02b%02b%02b%02b%02b",@injuries['nsys']['wound'],@injuries['leftEye']['wound'],@injuries['rightEye']['wound'],@injuries['back']['wound'],@injuries['abdomen']['wound'],@injuries['chest']['wound'],@injuries['leftHand']['wound'],@injuries['rightHand']['wound'],@injuries['leftLeg']['wound'],@injuries['rightLeg']['wound'],@injuries['leftArm']['wound'],@injuries['rightArm']['wound'],@injuries['neck']['wound'],@injuries['head']['wound'])
   end

   def make_scar_gsl
      @scar_gsl = sprintf("0b0%02b%02b%02b%02b%02b%02b%02b%02b%02b%02b%02b%02b%02b%02b",@injuries['nsys']['scar'],@injuries['leftEye']['scar'],@injuries['rightEye']['scar'],@injuries['back']['scar'],@injuries['abdomen']['scar'],@injuries['chest']['scar'],@injuries['leftHand']['scar'],@injuries['rightHand']['scar'],@injuries['leftLeg']['scar'],@injuries['rightLeg']['scar'],@injuries['leftArm']['scar'],@injuries['rightArm']['scar'],@injuries['neck']['scar'],@injuries['head']['scar'])
   end

   def parse(line)
      @buffer.concat(line)
      loop {
         if str = @buffer.slice!(/^[^<]+/)
            text(str.gsub(/&(lt|gt|quot|apos|amp)/) { @unescape[$1] })
         elsif str = @buffer.slice!(/^<\/[^<]+>/)
            element = /^<\/([^\s>\/]+)/.match(str).captures.first
            tag_end(element)
         elsif str = @buffer.slice!(/^<[^<]+>/)
            element = /^<([^\s>\/]+)/.match(str).captures.first
            attributes = Hash.new
            str.scan(/([A-z][A-z0-9_\-]*)=(["'])(.*?)\2/).each { |attr| attributes[attr[0]] = attr[2] }
            tag_start(element, attributes)
            tag_end(element) if str =~ /\/>$/
         else
            break
         end
      }
   end

   def tag_start(name, attributes)
      begin
         @active_tags.push(name)
         @active_ids.push(attributes['id'].to_s)
         if name =~ /^(?:a|right|left)$/
            @obj_exist = attributes['exist']
            @obj_noun = attributes['noun']
         elsif name == 'inv'
            if attributes['id'] == 'stow'
               @obj_location = @stow_container_id
            else
               @obj_location = attributes['id']
            end
            @obj_exist = nil
            @obj_noun = nil
            @obj_name = nil
            @obj_before_name = nil
            @obj_after_name = nil
         elsif name == 'dialogData' and attributes['id'] == 'ActiveSpells' and attributes['clear'] == 't'
            @active_spells.clear
         elsif name == 'resource' or name == 'nav'
            nil
         elsif name == 'pushStream'
            @in_stream = true
            @current_stream = attributes['id'].to_s
            GameObj.clear_inv if attributes['id'].to_s == 'inv'
         elsif name == 'popStream'
            if attributes['id'] == 'room'
               unless @room_window_disabled
                  @room_count += 1
                  $room_count += 1
               end
            end
            @in_stream = false
            if attributes['id'] == 'bounty'
               @bounty_task.strip!
            end
            @current_stream = String.new
         elsif name == 'pushBold'
            @bold = true
         elsif name == 'popBold'
            @bold = false
         elsif (name == 'streamWindow')
            if (attributes['id'] == 'main') and attributes['subtitle']
               @room_title = '[' + attributes['subtitle'][3..-1] + ']'
            end
         elsif name == 'style'
            @current_style = attributes['id']
         elsif name == 'prompt'
            @server_time = attributes['time'].to_i
            @server_time_offset = (Time.now.to_i - @server_time)
            $_CLIENT_.puts "\034GSq#{sprintf('%010d', @server_time)}\r\n" if @send_fake_tags
         elsif (name == 'compDef') or (name == 'component')
            if attributes['id'] == 'room objs'
               GameObj.clear_loot
               GameObj.clear_npcs
            elsif attributes['id'] == 'room players'
               GameObj.clear_pcs
            elsif attributes['id'] == 'room exits'
               @room_exits = Array.new
               @room_exits_string = String.new
            elsif attributes['id'] == 'room desc'
               @room_description = String.new
               GameObj.clear_room_desc
            elsif attributes['id'] == 'room extra' # DragonRealms
               @room_count += 1
               $room_count += 1
            # elsif attributes['id'] == 'sprite'
            end
         elsif name == 'clearContainer'
            if attributes['id'] == 'stow'
               GameObj.clear_container(@stow_container_id)
            else
               GameObj.clear_container(attributes['id'])
            end
         elsif name == 'deleteContainer'
            GameObj.delete_container(attributes['id'])
         elsif name == 'progressBar'
            if attributes['id'] == 'pbarStance'
               @stance_text = attributes['text'].split.first
               @stance_value = attributes['value'].to_i
               $_CLIENT_.puts "\034GSg#{sprintf('%010d', @stance_value)}\r\n" if @send_fake_tags
            elsif attributes['id'] == 'mana'
               last_mana = @mana
               @mana, @max_mana = attributes['text'].scan(/-?\d+/).collect { |num| num.to_i }
               difference = @mana - last_mana
               # fixme: enhancives screw this up
               if (difference == noded_pulse) or (difference == unnoded_pulse) or ( (@mana == @max_mana) and (last_mana + noded_pulse > @max_mana) )
                  @last_pulse = Time.now.to_i
                  if @send_fake_tags
                     $_CLIENT_.puts "\034GSZ#{sprintf('%010d',(@mana+1))}\n"
                     $_CLIENT_.puts "\034GSZ#{sprintf('%010d',@mana)}\n"
                  end
               end
               if @send_fake_tags
                  $_CLIENT_.puts "\034GSV#{sprintf('%010d%010d%010d%010d%010d%010d%010d%010d', @max_health.to_i, @health.to_i, @max_spirit.to_i, @spirit.to_i, @max_mana.to_i, @mana.to_i, @wound_gsl, @scar_gsl)}\r\n"
               end
            elsif attributes['id'] == 'stamina'
               @stamina, @max_stamina = attributes['text'].scan(/-?\d+/).collect { |num| num.to_i }
            elsif attributes['id'] == 'mindState'
               @mind_text = attributes['text']
               @mind_value = attributes['value'].to_i
               $_CLIENT_.puts "\034GSr#{MINDMAP[@mind_text]}\r\n" if @send_fake_tags
            elsif attributes['id'] == 'health'
               @health, @max_health = attributes['text'].scan(/-?\d+/).collect { |num| num.to_i }
               $_CLIENT_.puts "\034GSV#{sprintf('%010d%010d%010d%010d%010d%010d%010d%010d', @max_health.to_i, @health.to_i, @max_spirit.to_i, @spirit.to_i, @max_mana.to_i, @mana.to_i, @wound_gsl, @scar_gsl)}\r\n" if @send_fake_tags
            elsif attributes['id'] == 'spirit'
               @last_spirit = @spirit if @last_spirit
               @spirit, @max_spirit = attributes['text'].scan(/-?\d+/).collect { |num| num.to_i }
               @last_spirit = @spirit unless @last_spirit
               $_CLIENT_.puts "\034GSV#{sprintf('%010d%010d%010d%010d%010d%010d%010d%010d', @max_health.to_i, @health.to_i, @max_spirit.to_i, @spirit.to_i, @max_mana.to_i, @mana.to_i, @wound_gsl, @scar_gsl)}\r\n" if @send_fake_tags
            elsif attributes['id'] == 'nextLvlPB'
               Gift.pulse unless @next_level_text == attributes['text']
               @next_level_value = attributes['value'].to_i
               @next_level_text = attributes['text']
            elsif attributes['id'] == 'encumlevel'
               @encumbrance_value = attributes['value'].to_i
               @encumbrance_text = attributes['text']
            end
         elsif name == 'roundTime'
            @roundtime_end = attributes['value'].to_i
            $_CLIENT_.puts "\034GSQ#{sprintf('%010d', @roundtime_end)}\r\n" if @send_fake_tags
         elsif name == 'castTime'
            @cast_roundtime_end = attributes['value'].to_i
         elsif name == 'dropDownBox'
            if attributes['id'] == 'dDBTarget'
               @current_target_ids.clear
               attributes['content_value'].split(',').each { |t|
                  if t =~ /^\#(\-?\d+)(?:,|$)/
                     @current_target_ids.push($1)
                  end
               }
               if attributes['content_value'] =~ /^\#(\-?\d+)(?:,|$)/
                  @current_target_id = $1
               else
                  @current_target_id = nil
               end
            end
         elsif name == 'indicator'
            @indicator[attributes['id']] = attributes['visible']
            if @send_fake_tags
               if attributes['id'] == 'IconPOISONED'
                  if attributes['visible'] == 'y'
                     $_CLIENT_.puts "\034GSJ0000000000000000000100000000001\r\n"
                  else
                     $_CLIENT_.puts "\034GSJ0000000000000000000000000000000\r\n"
                  end
               elsif attributes['id'] == 'IconDISEASED'
                  if attributes['visible'] == 'y'
                     $_CLIENT_.puts "\034GSK0000000000000000000100000000001\r\n"
                  else
                     $_CLIENT_.puts "\034GSK0000000000000000000000000000000\r\n"
                  end
               else
                  gsl_prompt = String.new; ICONMAP.keys.each { |icon| gsl_prompt += ICONMAP[icon] if @indicator[icon] == 'y' }
                  $_CLIENT_.puts "\034GSP#{sprintf('%-30s', gsl_prompt)}\r\n"
               end
            end
         elsif (name == 'image') and @active_ids.include?('injuries')
            if @injuries.keys.include?(attributes['id'])
               if attributes['name'] =~ /Injury/i
                  @injuries[attributes['id']]['wound'] = attributes['name'].slice(/\d/).to_i
               elsif attributes['name'] =~ /Scar/i
                  @injuries[attributes['id']]['wound'] = 0
                  @injuries[attributes['id']]['scar'] = attributes['name'].slice(/\d/).to_i
               elsif attributes['name'] =~ /Nsys/i
                  rank = attributes['name'].slice(/\d/).to_i
                  if rank == 0
                     @injuries['nsys']['wound'] = 0
                     @injuries['nsys']['scar'] = 0
                  else
                     Thread.new {
                        wait_while { dead? }
                        action = proc { |server_string|
                           if (@nerve_tracker_active == 'maybe')
                              if @nerve_tracker_active == 'maybe'
                                 if server_string =~ /^You/
                                    @nerve_tracker_active = 'yes'
                                    @injuries['nsys']['wound'] = 0
                                    @injuries['nsys']['scar'] = 0
                                 else
                                    @nerve_tracker_active = 'no'
                                 end
                              end
                           end
                           if @nerve_tracker_active == 'yes'
                              if server_string =~ /<output class=['"]['"]\/>/
                                 @nerve_tracker_active = 'no'
                                 @nerve_tracker_num -= 1
                                 DownstreamHook.remove('nerve_tracker') if @nerve_tracker_num < 1
                                 $_CLIENT_.puts "\034GSV#{sprintf('%010d%010d%010d%010d%010d%010d%010d%010d', @max_health.to_i, @health.to_i, @max_spirit.to_i, @spirit.to_i, @max_mana.to_i, @mana.to_i, make_wound_gsl, make_scar_gsl)}\r\n" if @send_fake_tags
                                 server_string
                              elsif server_string =~ /a case of uncontrollable convulsions/
                                 @injuries['nsys']['wound'] = 3
                                 nil
                              elsif server_string =~ /a case of sporadic convulsions/
                                 @injuries['nsys']['wound'] = 2
                                 nil
                              elsif server_string =~ /a strange case of muscle twitching/
                                 @injuries['nsys']['wound'] = 1
                                 nil
                              elsif server_string =~ /a very difficult time with muscle control/
                                 @injuries['nsys']['scar'] = 3
                                 nil
                              elsif server_string =~ /constant muscle spasms/
                                 @injuries['nsys']['scar'] = 2
                                 nil
                              elsif server_string =~ /developed slurred speech/
                                 @injuries['nsys']['scar'] = 1
                                 nil
                              end
                           else
                              if server_string =~ /<output class=['"]mono['"]\/>/
                                 @nerve_tracker_active = 'maybe'
                              end
                              server_string
                           end
                        }
                        @nerve_tracker_num += 1
                        DownstreamHook.add('nerve_tracker', action)
                        Game._puts "#{$cmd_prefix}health"
                     }
                  end
               else
                  @injuries[attributes['id']]['wound'] = 0
                  @injuries[attributes['id']]['scar'] = 0
               end
            end
            $_CLIENT_.puts "\034GSV#{sprintf('%010d%010d%010d%010d%010d%010d%010d%010d', @max_health.to_i, @health.to_i, @max_spirit.to_i, @spirit.to_i, @max_mana.to_i, @mana.to_i, make_wound_gsl, make_scar_gsl)}\r\n" if @send_fake_tags
         elsif name == 'compass'
            if @current_stream == 'familiar'
               @fam_mode = String.new
            elsif @room_window_disabled
               @room_exits = Array.new
            end
         elsif @room_window_disabled and (name == 'dir') and @active_tags.include?('compass')
            @room_exits.push(LONGDIR[attributes['value']])
         elsif name == 'radio'
            if attributes['id'] == 'injrRad'
               @injury_mode = 0 if attributes['value'] == '1'
            elsif attributes['id'] == 'scarRad'
               @injury_mode = 1 if attributes['value'] == '1'
            elsif attributes['id'] == 'bothRad'
               @injury_mode = 2 if attributes['value'] == '1'
            end
         elsif name == 'label'
            if attributes['id'] == 'yourLvl'
               @level = Stats.level = attributes['value'].slice(/\d+/).to_i
            elsif attributes['id'] == 'encumblurb'
               @encumbrance_full_text = attributes['value']
            elsif @active_tags[-2] == 'dialogData' and @active_ids[-2] == 'ActiveSpells'
               if (name = /^lbl(.+)$/.match(attributes['id']).captures.first) and (value = /^\s*([0-9\:]+)\s*$/.match(attributes['value']).captures.first)
                  hour, minute = value.split(':')
                  @active_spells[name] = Time.now + (hour.to_i * 3600) + (minute.to_i * 60)
               end
            end
         elsif (name == 'container') and (attributes['id'] == 'stow')
            @stow_container_id = attributes['target'].sub('#', '')
         elsif (name == 'clearStream')
            if attributes['id'] == 'bounty'
               @bounty_task = String.new
            end
         elsif (name == 'playerID')
            @player_id = attributes['id']
            unless $frontend =~ /^(?:wizard|avalon)$/
               if Lich.inventory_boxes(@player_id)
                  DownstreamHook.remove('inventory_boxes_off')
               end
            end
         elsif name == 'settingsInfo'
            if game = attributes['instance']
               if game == 'GS4'
                  @game = 'GSIV'
               elsif (game == 'GSX') or (game == 'GS4X')
                  @game = 'GSPlat'
               else
                  @game = game
               end
            end
         elsif (name == 'app') and (@name = attributes['char'])
            if @game.nil? or @game.empty?
               @game = 'unknown'
            end
            unless File.exists?("#{DATA_DIR}/#{@game}")
               Dir.mkdir("#{DATA_DIR}/#{@game}")
            end
            unless File.exists?("#{DATA_DIR}/#{@game}/#{@name}")
               Dir.mkdir("#{DATA_DIR}/#{@game}/#{@name}")
            end
            if $frontend =~ /^(?:wizard|avalon)$/
               Game._puts "#{$cmd_prefix}_flag Display Dialog Boxes 0"
               sleep 0.05
               Game._puts "#{$cmd_prefix}_injury 2"
               sleep 0.05
               # fixme: game name hardcoded as Gemstone IV; maybe doesn't make any difference to the client
               $_CLIENT_.puts "\034GSB0000000000#{attributes['char']}\r\n\034GSA#{Time.now.to_i.to_s}GemStone IV\034GSD\r\n"
               # Sending fake GSL tags to the Wizard FE is disabled until now, because it doesn't accept the tags and just gives errors until initialized with the above line
               @send_fake_tags = true
               # Send all the tags we missed out on
               $_CLIENT_.puts "\034GSV#{sprintf('%010d%010d%010d%010d%010d%010d%010d%010d', @max_health.to_i, @health.to_i, @max_spirit.to_i, @spirit.to_i, @max_mana.to_i, @mana.to_i, make_wound_gsl, make_scar_gsl)}\r\n"
               $_CLIENT_.puts "\034GSg#{sprintf('%010d', @stance_value)}\r\n"
               $_CLIENT_.puts "\034GSr#{MINDMAP[@mind_text]}\r\n"
               gsl_prompt = String.new
               @indicator.keys.each { |icon| gsl_prompt += ICONMAP[icon] if @indicator[icon] == 'y' }
               $_CLIENT_.puts "\034GSP#{sprintf('%-30s', gsl_prompt)}\r\n"
               gsl_prompt = nil
               gsl_exits = String.new
               @room_exits.each { |exit| gsl_exits.concat(DIRMAP[SHORTDIR[exit]].to_s) }
               $_CLIENT_.puts "\034GSj#{sprintf('%-20s', gsl_exits)}\r\n"
               gsl_exits = nil
               $_CLIENT_.puts "\034GSn#{sprintf('%-14s', @prepared_spell)}\r\n"
               $_CLIENT_.puts "\034GSm#{sprintf('%-45s', GameObj.right_hand.name)}\r\n"
               $_CLIENT_.puts "\034GSl#{sprintf('%-45s', GameObj.left_hand.name)}\r\n"
               $_CLIENT_.puts "\034GSq#{sprintf('%010d', @server_time)}\r\n"
               $_CLIENT_.puts "\034GSQ#{sprintf('%010d', @roundtime_end)}\r\n" if @roundtime_end > 0
            end
            Game._puts("#{$cmd_prefix}_flag Display Inventory Boxes 1")

            Thread.new { 
               begin
                  Autostart.call
               rescue Exception => e
                  puts e
                  respond e
               end
            }

            if arg = ARGV.find { |a| a=~ /^\-\-start\-scripts=/ }
               for script_name in arg.sub('--start-scripts=', '').split(',')
                  Script.start(script_name)
               end
            end
         end
      rescue
         $stdout.puts "--- error: XMLParser.tag_start: #{$!}"
         Lich.log "error: XMLParser.tag_start: #{$!}\n\t#{$!.backtrace.join("\n\t")}"
         sleep 0.1
         reset
      end
   end
   def text(text_string)
      begin
         # fixme: /<stream id="Spells">.*?<\/stream>/m
         # $_CLIENT_.write(text_string) unless ($frontend != 'suks') or (@current_stream =~ /^(?:spellfront|inv|bounty|society)$/) or @active_tags.any? { |tag| tag =~ /^(?:compDef|inv|component|right|left|spell)$/ } or (@active_tags.include?('stream') and @active_ids.include?('Spells')) or (text_string == "\n" and (@last_tag =~ /^(?:popStream|prompt|compDef|dialogData|openDialog|switchQuickBar|component)$/))
         if @active_tags.include?('inv')
            if @active_tags[-1] == 'a'
               @obj_name = text_string
            elsif @obj_name.nil?
               @obj_before_name = text_string.strip
            else
               @obj_after_name = text_string.strip
            end
         elsif @active_tags.last == 'prompt'
            @prompt = text_string
         elsif @active_tags.include?('right')
            GameObj.new_right_hand(@obj_exist, @obj_noun, text_string)
            $_CLIENT_.puts "\034GSm#{sprintf('%-45s', text_string)}\r\n" if @send_fake_tags
         elsif @active_tags.include?('left')
            GameObj.new_left_hand(@obj_exist, @obj_noun, text_string)
            $_CLIENT_.puts "\034GSl#{sprintf('%-45s', text_string)}\r\n" if @send_fake_tags
         elsif @active_tags.include?('spell')
            @prepared_spell = text_string
            $_CLIENT_.puts "\034GSn#{sprintf('%-14s', text_string)}\r\n" if @send_fake_tags
         elsif @active_tags.include?('compDef') or @active_tags.include?('component')
            if @active_ids.include?('room objs')
               if @active_tags.include?('a')
                  if @bold
                     GameObj.new_npc(@obj_exist, @obj_noun, text_string)
                  else
                     GameObj.new_loot(@obj_exist, @obj_noun, text_string)
                  end
               elsif (text_string =~ /that (?:is|appears) ([\w\s]+)(?:,| and|\.)/) or (text_string =~ / \(([^\(]+)\)/)
                  GameObj.npcs[-1].status = $1
               end
            elsif @active_ids.include?('room players')
               if @active_tags.include?('a')
                  @pc = GameObj.new_pc(@obj_exist, @obj_noun, "#{@player_title}#{text_string}", @player_status)
                  @player_status = nil
               else
                  if @game =~ /^DR/
                     GameObj.clear_pcs
                     text_string.sub(/^Also here\: /, '').sub(/ and ([^,]+)\./) { ", #{$1}" }.split(', ').each { |player|
                        if player =~ / who is (.+)/
                           status = $1
                           player.sub!(/ who is .+/, '')
                        elsif player =~ / \((.+)\)/
                           status = $1
                           player.sub!(/ \(.+\)/, '')
                        else
                           status = nil
                        end
                        noun = player.slice(/\b[A-Z][a-z]+$/)
                        if player =~ /the body of /
                           player.sub!('the body of ', '')
                           if status
                              status.concat ' dead'
                           else
                              status = 'dead'
                           end
                        end
                        if player =~ /a stunned /
                           player.sub!('a stunned ', '')
                           if status
                              status.concat ' stunned'
                           else
                              status = 'stunned'
                           end
                        end
                        GameObj.new_pc(nil, noun, player, status)
                     }
                  else
                     if (text_string =~ /^ who (?:is|appears) ([\w\s]+)(?:,| and|\.|$)/) or (text_string =~ / \(([\w\s]+)\)(?: \(([\w\s]+)\))?/)
                        if @pc.status
                           @pc.status.concat " #{$1}"
                        else
                           @pc.status = $1
                        end
                        @pc.status.concat " #{$2}" if $2
                     end
                     if text_string =~ /(?:^Also here: |, )(?:a )?([a-z\s]+)?([\w\s\-!\?',]+)?$/
                        @player_status = ($1.strip.gsub('the body of', 'dead')) if $1
                        @player_title = $2
                     end
                  end
               end
            elsif @active_ids.include?('room desc')
               if text_string == '[Room window disabled at this location.]'
                  @room_window_disabled = true
               else
                  @room_window_disabled = false
                  @room_description.concat(text_string)
                  if @active_tags.include?('a')
                     GameObj.new_room_desc(@obj_exist, @obj_noun, text_string)
                  end
               end
            elsif @active_ids.include?('room exits')
               @room_exits_string.concat(text_string)
               @room_exits.push(text_string) if @active_tags.include?('d')
            end
         elsif @current_stream == 'bounty'
            @bounty_task += text_string
         elsif @current_stream == 'society'
            @society_task = text_string
         elsif (@current_stream == 'inv') and @active_tags.include?('a')
            GameObj.new_inv(@obj_exist, @obj_noun, text_string, nil)
         elsif @current_stream == 'familiar'
            # fixme: familiar room tracking does not (can not?) auto update, status of pcs and npcs isn't tracked at all, titles of pcs aren't tracked
            if @current_style == 'roomName'
               @familiar_room_title = text_string
               @familiar_room_description = String.new
               @familiar_room_exits = Array.new
               GameObj.clear_fam_room_desc
               GameObj.clear_fam_loot
               GameObj.clear_fam_npcs
               GameObj.clear_fam_pcs
               @fam_mode = String.new
            elsif @current_style == 'roomDesc'
               @familiar_room_description.concat(text_string)
               if @active_tags.include?('a')
                  GameObj.new_fam_room_desc(@obj_exist, @obj_noun, text_string)
               end
            elsif text_string =~ /^You also see/
               @fam_mode = 'things'
            elsif text_string =~ /^Also here/
               @fam_mode = 'people'
            elsif text_string =~ /Obvious (?:paths|exits)/
               @fam_mode = 'paths'
            elsif @fam_mode == 'things'
               if @active_tags.include?('a')
                  if @bold
                     GameObj.new_fam_npc(@obj_exist, @obj_noun, text_string)
                  else
                     GameObj.new_fam_loot(@obj_exist, @obj_noun, text_string)
                  end
               end
               # puts 'things: ' + text_string
            elsif @fam_mode == 'people' and @active_tags.include?('a')
               GameObj.new_fam_pc(@obj_exist, @obj_noun, text_string)
               # puts 'people: ' + text_string
            elsif (@fam_mode == 'paths') and @active_tags.include?('a')
               @familiar_room_exits.push(text_string)
            end
         elsif @room_window_disabled
            if @current_style == 'roomDesc'
               @room_description.concat(text_string)
               if @active_tags.include?('a')
                  GameObj.new_room_desc(@obj_exist, @obj_noun, text_string)
               end
            elsif text_string =~ /^Obvious (?:paths|exits): (?:none)?$/
               @room_exits_string = text_string.strip
            end
         end
      rescue
         $stdout.puts "--- error: XMLParser.text: #{$!}"
         Lich.log "error: XMLParser.text: #{$!}\n\t#{$!.backtrace.join("\n\t")}"
         sleep 0.1
         reset
      end
   end
   def tag_end(name)
      begin
         if name == 'inv'
            if @obj_exist == @obj_location
               if @obj_after_name == 'is closed.'
                  GameObj.delete_container(@stow_container_id)
               end
            elsif @obj_exist
               GameObj.new_inv(@obj_exist, @obj_noun, @obj_name, @obj_location, @obj_before_name, @obj_after_name)
            end
         elsif @send_fake_tags and (@active_ids.last == 'room exits')
            gsl_exits = String.new
            @room_exits.each { |exit| gsl_exits.concat(DIRMAP[SHORTDIR[exit]].to_s) }
            $_CLIENT_.puts "\034GSj#{sprintf('%-20s', gsl_exits)}\r\n"
            gsl_exits = nil
         elsif @room_window_disabled and (name == 'compass')

            @room_description = @room_description.strip
            @room_exits_string.concat " #{@room_exits.join(', ')}" unless @room_exits.empty?
            gsl_exits = String.new
            @room_exits.each { |exit| gsl_exits.concat(DIRMAP[SHORTDIR[exit]].to_s) }
            $_CLIENT_.puts "\034GSj#{sprintf('%-20s', gsl_exits)}\r\n"
            gsl_exits = nil
            @room_count += 1
            $room_count += 1
         end
         @last_tag = @active_tags.pop
         @last_id = @active_ids.pop
      rescue
         $stdout.puts "--- error: XMLParser.tag_end: #{$!}"
         Lich.log "error: XMLParser.tag_end: #{$!}\n\t#{$!.backtrace.join("\n\t")}"
         sleep 0.1
         reset
      end
   end
   # here for backwards compatibility, but spellfront xml isn't sent by the game anymore
   def spellfront
      if (Time.now.to_i - @@warned_deprecated_spellfront) > 300
         @@warned_deprecated_spellfront = Time.now.to_i
         unless script_name = Script.current.name
            script_name = 'unknown script'
         end
         respond "--- warning: #{script_name} is using deprecated method XMLData.spellfront; this method will be removed in a future version of Lich"
      end
      @active_spells.keys
   end
end

class UpstreamHook
   @@upstream_hooks ||= Hash.new
   def UpstreamHook.add(name, action)
      unless action.class == Proc
         echo "UpstreamHook: not a Proc (#{action})"
         return false
      end
      @@upstream_hooks[name] = action
   end
   def UpstreamHook.run(client_string)
      for key in @@upstream_hooks.keys
         begin
            client_string = @@upstream_hooks[key].call(client_string)
         rescue
            @@upstream_hooks.delete(key)
            respond "--- Lich: UpstreamHook: #{$!}"
            respond $!.backtrace.first
         end
         return nil if client_string.nil?
      end
      return client_string
   end
   def UpstreamHook.remove(name)
      @@upstream_hooks.delete(name)
   end
   def UpstreamHook.list
      @@upstream_hooks.keys.dup
   end
end

class DownstreamHook
   @@downstream_hooks ||= Hash.new
   def DownstreamHook.add(name, action)
      unless action.class == Proc
         echo "DownstreamHook: not a Proc (#{action})"
         return false
      end
      @@downstream_hooks[name] = action
   end
   def DownstreamHook.run(server_string)
      for key in @@downstream_hooks.keys
         begin
            exec_time = Benchmark.realtime {
               server_string = @@downstream_hooks[key].call(server_string.dup)
            }
            if (exec_time * 1_000 > 50)
               respond "warning(downstreamhook::#{key}) took #{exec_time * 1_000}"
            end
         rescue
            @@downstream_hooks.delete(key)
            respond "--- Lich: DownstreamHook: #{$!}"
            respond $!.backtrace.first
         end
         return nil if server_string.nil?
      end
      return server_string
   end
   def DownstreamHook.remove(name)
      @@downstream_hooks.delete(name)
   end
   def DownstreamHook.list
      @@downstream_hooks.keys.dup
   end
end

module Setting
   @@load = proc { |args|
      unless script = Script.current
         respond '--- error: Setting.load: calling script is unknown'
         respond $!.backtrace[0..2]
         next nil
      end
      if script.class == ExecScript
         respond "--- Lich: error: Setting.load: exec scripts can't have settings"
         respond $!.backtrace[0..2]
         exit
      end
      if args.empty?
         respond '--- error: Setting.load: no setting specified'
         respond $!.backtrace[0..2]
         exit
      end
      if args.any? { |a| a.class != String }
         respond "--- Lich: error: Setting.load: non-string given as setting name"
         respond $!.backtrace[0..2]
         exit
      end
      values = Array.new
      for setting in args
         begin
            v = Lich.db.get_first_value('SELECT value FROM script_setting WHERE script=? AND name=?;', script.name.encode('UTF-8'), setting.encode('UTF-8'))
         rescue SQLite3::BusyException
            sleep 0.1
            retry
         end
         if v.nil?
            values.push(v)
         else
            begin
               values.push(Marshal.load(v))
            rescue
               respond "--- Lich: error: Setting.load: #{$!}"
               respond $!.backtrace[0..2]
               exit
            end
         end
      end
      if args.length == 1
         next values[0]
      else
         next values
      end
   }
   @@save = proc { |hash|
      unless script = Script.current
         respond '--- error: Setting.save: calling script is unknown'
         respond $!.backtrace[0..2]
         next nil
      end
      if script.class == ExecScript
         respond "--- Lich: error: Setting.load: exec scripts can't have settings"
         respond $!.backtrace[0..2]
         exit
      end
      if hash.class != Hash
         respond "--- Lich: error: Setting.save: invalid arguments: use Setting.save('setting1' => 'value1', 'setting2' => 'value2')"
         respond $!.backtrace[0..2]
         exit
      end
      if hash.empty?
         next nil
      end
      if hash.keys.any? { |k| k.class != String }
         respond "--- Lich: error: Setting.save: non-string given as a setting name"
         respond $!.backtrace[0..2]
         exit
      end
      if hash.length > 1
         begin
            Lich.db.execute('BEGIN')
         rescue SQLite3::BusyException
            sleep 0.1
            retry
         end
      end
      hash.each { |setting,value|
         begin
            if value.nil?
               begin
                  Lich.db.execute('DELETE FROM script_setting WHERE script=? AND name=?;', script.name.encode('UTF-8'), setting.encode('UTF-8'))
               rescue SQLite3::BusyException
                  sleep 0.1
                  retry
               end
            else
               v = SQLite3::Blob.new(Marshal.dump(value))
               begin
                  Lich.db.execute('INSERT OR REPLACE INTO script_setting(script,name,value) VALUES(?,?,?);', script.name.encode('UTF-8'), setting.encode('UTF-8'), v)
               rescue SQLite3::BusyException
                  sleep 0.1
                  retry
               end
            end
         rescue SQLite3::BusyException
            sleep 0.1
            retry
         end
      }
      if hash.length > 1
         begin
            Lich.db.execute('END')
         rescue SQLite3::BusyException
            sleep 0.1
            retry
         end
      end
      true
   }
   @@list = proc {
      unless script = Script.current
         respond '--- error: Setting: unknown calling script'
         next nil
      end
      if script.class == ExecScript
         respond "--- Lich: error: Setting.load: exec scripts can't have settings"
         respond $!.backtrace[0..2]
         exit
      end
      begin
         rows = Lich.db.execute('SELECT name FROM script_setting WHERE script=?;', script.name.encode('UTF-8'))
      rescue SQLite3::BusyException
         sleep 0.1
         retry
      end
      if rows
         # fixme
         next rows.inspect
      else
         next nil
      end
   }
   def Setting.load(*args)
      @@load.call(args)
   end
   def Setting.save(hash)
      @@save.call(hash)
   end
   def Setting.list
      @@list.call
   end
end

module GameSetting
   def GameSetting.load(*args)
      Setting.load(args.collect { |a| "#{XMLData.game}:#{a}" })
   end
   def GameSetting.save(hash)
      game_hash = Hash.new
      hash.each_pair { |k,v| game_hash["#{XMLData.game}:#{k}"] = v }
      Setting.save(game_hash)
   end
end

module CharSetting
   def CharSetting.load(*args)
      Setting.load(args.collect { |a| "#{XMLData.game}:#{XMLData.name}:#{a}" })
   end
   def CharSetting.save(hash)
      game_hash = Hash.new
      hash.each_pair { |k,v| game_hash["#{XMLData.game}:#{XMLData.name}:#{k}"] = v }
      Setting.save(game_hash)
   end
end

module GameSettings
   def GameSettings.[](name)
      Settings.to_hash(XMLData.game)[name]
   end
   def GameSettings.[]=(name, value)
      Settings.to_hash(XMLData.game)[name] = value
   end
   def GameSettings.to_hash
      Settings.to_hash(XMLData.game)
   end
end

module Vars
   @@vars   = Hash.new
   md5      = nil
   mutex    = Mutex.new
   @@loaded = false
   @@load = proc {
      mutex.synchronize {
         unless @@loaded
            begin
               h = Lich.db.get_first_value('SELECT hash FROM uservars WHERE scope=?;', "#{XMLData.game}:#{XMLData.name}".encode('UTF-8'))
            rescue SQLite3::BusyException
               sleep 0.1
               retry
            end
            if h
               begin
                  hash = Marshal.load(h)
                  hash.each { |k,v| @@vars[k] = v }
                  md5 = Digest::MD5.hexdigest(hash.to_s)
               rescue
                  respond "--- Lich: error: #{$!}"
                  respond $!.backtrace[0..2]
               end
            end
            @@loaded = true
         end
      }
      nil
   }
   @@save = proc {
      mutex.synchronize {
         if @@loaded
            if Digest::MD5.hexdigest(@@vars.to_s) != md5
               md5 = Digest::MD5.hexdigest(@@vars.to_s)
               blob = SQLite3::Blob.new(Marshal.dump(@@vars))
               begin
                  Lich.db.execute('INSERT OR REPLACE INTO uservars(scope,hash) VALUES(?,?);', "#{XMLData.game}:#{XMLData.name}".encode('UTF-8'), blob)
               rescue SQLite3::BusyException
                  sleep 0.1
                  retry
               end
            end
         end
      }
      nil
   }
   Thread.new {
      loop {
         sleep 300
         begin
            @@save.call
         rescue
            Lich.log "error: #{$!}\n\t#{$!.backtrace.join("\n\t")}"
            respond "--- Lich: error: #{$!}\n\t#{$!.backtrace[0..1].join("\n\t")}"
         end
      }
   }
   def Vars.[](name)
      @@load.call unless @@loaded
      @@vars[name]
   end
   def Vars.[]=(name, val)
      @@load.call unless @@loaded
      if val.nil?
         @@vars.delete(name)
      else
         @@vars[name] = val
      end
   end
   def Vars.list
      @@load.call unless @@loaded
      @@vars.dup
   end
   def Vars.save
      @@save.call
   end
   def Vars.method_missing(arg1, arg2='')
      @@load.call unless @@loaded
      if arg1[-1,1] == '='
         if arg2.nil?
            @@vars.delete(arg1.to_s.chop)
         else
            @@vars[arg1.to_s.chop] = arg2
         end
      else
         @@vars[arg1.to_s]
      end
   end
end

class Watchfor
   def initialize(line, theproc=nil, &block)
      return nil unless script = Script.current
      if line.class == String
         line = Regexp.new(Regexp.escape(line))
      elsif line.class != Regexp
         echo 'watchfor: no string or regexp given'
         return nil
      end
      if block.nil?
         if theproc.respond_to? :call
            block = theproc
         else
            echo 'watchfor: no block or proc given'
            return nil
         end
      end
      script.watchfor[line] = block
   end
   def Watchfor.clear
      script.watchfor = Hash.new
   end
end

class Thread
  alias_method :_initialize, :initialize

  def initialize(*args, &block)
    @_parent = Thread.current if Thread.current.is_a?(Script)
    _initialize(*args, &block)
  end

  def parent
    @_parent
  end

  def dispose()
    @_parent = nil
  end
end

require_relative("./lib/script")
require_relative("./lib/exec-script")
require_relative("./lib/map")
require_relative("./lib/room")
require_relative("./lib/autostart")
require_relative("./lib/settings")
require_relative("./lib/char-settings")
require_relative("./lib/format")
require_relative("./lib/globals")

$link_highlight_start = ''
$link_highlight_end = ''
$speech_highlight_start = ''
$speech_highlight_end = ''

def sf_to_wiz(line)
   begin
      return line if line == "\r\n"

      if $sftowiz_multiline
         $sftowiz_multiline = $sftowiz_multiline + line
         line = $sftowiz_multiline
      end
      if (line.scan(/<pushStream[^>]*\/>/).length > line.scan(/<popStream[^>]*\/>/).length)
         $sftowiz_multiline = line
         return nil
      end
      if (line.scan(/<style id="\w+"[^>]*\/>/).length > line.scan(/<style id=""[^>]*\/>/).length)
         $sftowiz_multiline = line
         return nil
      end
      $sftowiz_multiline = nil
      if line =~ /<LaunchURL src="(.*?)" \/>/
         $_CLIENT_.puts "\034GSw00005\r\nhttps://www.play.net#{$1}\r\n"
      end
      if line =~ /<preset id='speech'>(.*?)<\/preset>/m
         line = line.sub(/<preset id='speech'>.*?<\/preset>/m, "#{$speech_highlight_start}#{$1}#{$speech_highlight_end}")
      end
      if line =~ /<pushStream id="thoughts"[^>]*>(?:<a[^>]*>)?([A-Z][a-z]+)(?:<\/a>)?\s*([\s\[\]\(\)A-z]+)?:(.*?)<popStream\/>/m
         line = line.sub(/<pushStream id="thoughts"[^>]*>(?:<a[^>]*>)?[A-Z][a-z]+(?:<\/a>)?\s*[\s\[\]\(\)A-z]+:.*?<popStream\/>/m, "You hear the faint thoughts of #{$1} echo in your mind:\r\n#{$2}#{$3}")
      end
      if line =~ /<pushStream id="voln"[^>]*>\[Voln \- (?:<a[^>]*>)?([A-Z][a-z]+)(?:<\/a>)?\]\s*(".*")[\r\n]*<popStream\/>/m
         line = line.sub(/<pushStream id="voln"[^>]*>\[Voln \- (?:<a[^>]*>)?([A-Z][a-z]+)(?:<\/a>)?\]\s*(".*")[\r\n]*<popStream\/>/m, "The Symbol of Thought begins to burn in your mind and you hear #{$1} thinking, #{$2}\r\n")
      end
      if line =~ /<stream id="thoughts"[^>]*>([^:]+): (.*?)<\/stream>/m
         line = line.sub(/<stream id="thoughts"[^>]*>.*?<\/stream>/m, "You hear the faint thoughts of #{$1} echo in your mind:\r\n#{$2}")
      end
      if line =~ /<pushStream id="familiar"[^>]*>(.*)<popStream\/>/m
         line = line.sub(/<pushStream id="familiar"[^>]*>.*<popStream\/>/m, "\034GSe\r\n#{$1}\034GSf\r\n")
      end
      if line =~ /<pushStream id="death"\/>(.*?)<popStream\/>/m
         line = line.sub(/<pushStream id="death"\/>.*?<popStream\/>/m, "\034GSw00003\r\n#{$1}\034GSw00004\r\n")
      end
      if line =~ /<style id="roomName" \/>(.*?)<style id=""\/>/m
         line = line.sub(/<style id="roomName" \/>.*?<style id=""\/>/m, "\034GSo\r\n#{$1}\034GSp\r\n")
      end
      line.gsub!(/<style id="roomDesc"\/><style id=""\/>\r?\n/, '')
      if line =~ /<style id="roomDesc"\/>(.*?)<style id=""\/>/m
         desc = $1.gsub(/<a[^>]*>/, $link_highlight_start).gsub("</a>", $link_highlight_end)
         line = line.sub(/<style id="roomDesc"\/>.*?<style id=""\/>/m, "\034GSH\r\n#{desc}\034GSI\r\n")
      end
      line = line.gsub("</prompt>\r\n", "</prompt>")
      line = line.gsub("<pushBold/>", "\034GSL\r\n")
      line = line.gsub("<popBold/>", "\034GSM\r\n")
      line = line.gsub(/<pushStream id=["'](?:spellfront|inv|bounty|society|speech|talk)["'][^>]*\/>.*?<popStream[^>]*>/m, '')
      line = line.gsub(/<stream id="Spells">.*?<\/stream>/m, '')
      line = line.gsub(/<(compDef|inv|component|right|left|spell|prompt)[^>]*>.*?<\/\1>/m, '')
      line = line.gsub(/<[^>]+>/, '')
      line = line.gsub('&gt;', '>')
      line = line.gsub('&lt;', '<')
      return nil if line.gsub("\r\n", '').length < 1
      return line
   rescue
      $_CLIENT_.puts "--- Error: sf_to_wiz: #{$!}"
      $_CLIENT_.puts '$_SERVERSTRING_: ' + $_SERVERSTRING_.to_s
   end
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

def monsterbold_start
   if $frontend =~ /^(?:wizard|avalon)$/
      "\034GSL\r\n"
   elsif $frontend == 'stormfront'
      '<pushBold/>'
   elsif $frontend == 'profanity'
      '<b>'
   else
      ''
   end
end

def monsterbold_end
   if $frontend =~ /^(?:wizard|avalon)$/
      "\034GSM\r\n"
   elsif $frontend == 'stormfront'
      '<popBold/>'
   elsif $frontend == 'profanity'
      '</b>'
   else
      ''
   end
end

def do_client(client_string)
   client_string.strip!
#   Buffer.update(client_string, Buffer::UPSTREAM)
   client_string = UpstreamHook.run(client_string)
#   Buffer.update(client_string, Buffer::UPSTREAM_MOD)
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
            .find { |s| s.name == target or s.name.downcase.end_with?(target.downcase) }
         if script.nil?
            respond "--- Lich: #{target} does not appear to be running! Use ';list' or ';listall' to see what's active."
         elsif action =~ /^(?:k|kill|stop)$/
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
      elsif cmd =~ /^trust\s+(.*)/i
         script_name = $1
         if RUBY_VERSION =~ /^2\.[012]\./
            if File.exists?("#{SCRIPT_DIR}/#{script_name}.lic")
               if Script.trust(script_name)
                  respond "--- Lich: '#{script_name}' is now a trusted script."
               else
                  respond "--- Lich: '#{script_name}' is already trusted."
               end
            else
               respond "--- Lich: could not find script: #{script_name}"
            end
         else
            respond "--- Lich: this feature isn't available in this version of Ruby "
         end
      elsif cmd =~ /^(?:dis|un)trust\s+(.*)/i
         script_name = $1
         if RUBY_VERSION =~ /^2\.[012]\./
            if Script.distrust(script_name)
               respond "--- Lich: '#{script_name}' is no longer a trusted script."
            else
               respond "--- Lich: '#{script_name}' was not found in the trusted script list."
            end
         else
            respond "--- Lich: this feature isn't available in this version of Ruby "
         end
      elsif cmd =~ /^list\s?(?:un)?trust(?:ed)?$|^lt$/i
         if RUBY_VERSION =~ /^2\.[012]\./
            list = Script.list_trusted
            if list.empty?
               respond "--- Lich: no scripts are trusted"
            else
               respond "--- Lich: trusted scripts: #{list.join(', ')}"
            end
            list = nil
         else
            respond "--- Lich: this feature isn't available in this version of Ruby "
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
         respond
         if (RUBY_VERSION =~ /^2\.[012]\./)
            respond "   #{$clean_lich_char}trust <script name>       let the script do whatever it wants"
            respond "   #{$clean_lich_char}distrust <script name>    restrict the script from doing things that might harm your computer"
            respond "   #{$clean_lich_char}list trusted              show what scripts are trusted"
            respond "   #{$clean_lich_char}lt                        ''"
            respond
         end
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

def report_errors(&block)
   begin
      block.call
   rescue
      respond "--- Lich: error: #{$!}\n\t#{$!.backtrace[0..1].join("\n\t")}"
      Lich.log "error: #{$!}\n\t#{$!.backtrace.join("\n\t")}"
   rescue SyntaxError
      respond "--- Lich: error: #{$!}\n\t#{$!.backtrace[0..1].join("\n\t")}"
      Lich.log "error: #{$!}\n\t#{$!.backtrace.join("\n\t")}"
   rescue SystemExit
      nil
   rescue SecurityError
      respond "--- Lich: error: #{$!}\n\t#{$!.backtrace[0..1].join("\n\t")}"
      Lich.log "error: #{$!}\n\t#{$!.backtrace.join("\n\t")}"
   rescue ThreadError
      respond "--- Lich: error: #{$!}\n\t#{$!.backtrace[0..1].join("\n\t")}"
      Lich.log "error: #{$!}\n\t#{$!.backtrace.join("\n\t")}"
   rescue SystemStackError
      respond "--- Lich: error: #{$!}\n\t#{$!.backtrace[0..1].join("\n\t")}"
      Lich.log "error: #{$!}\n\t#{$!.backtrace.join("\n\t")}"
   rescue Exception
      respond "--- Lich: error: #{$!}\n\t#{$!.backtrace[0..1].join("\n\t")}"
      Lich.log "error: #{$!}\n\t#{$!.backtrace.join("\n\t")}"
   rescue ScriptError
      respond "--- Lich: error: #{$!}\n\t#{$!.backtrace[0..1].join("\n\t")}"
      Lich.log "error: #{$!}\n\t#{$!.backtrace.join("\n\t")}"
   rescue LoadError
      respond "--- Lich: error: #{$!}\n\t#{$!.backtrace[0..1].join("\n\t")}"
      Lich.log "error: #{$!}\n\t#{$!.backtrace.join("\n\t")}"
   rescue NoMemoryError
      respond "--- Lich: error: #{$!}\n\t#{$!.backtrace[0..1].join("\n\t")}"
      Lich.log "error: #{$!}\n\t#{$!.backtrace.join("\n\t")}"
   rescue
      respond "--- Lich: error: #{$!}\n\t#{$!.backtrace[0..1].join("\n\t")}"
      Lich.log "error: #{$!}\n\t#{$!.backtrace.join("\n\t")}"
   end
end

module Buffer
   DOWNSTREAM_STRIPPED = 1
   DOWNSTREAM_RAW      = 2
   DOWNSTREAM_MOD      = 4
   UPSTREAM            = 8
   UPSTREAM_MOD        = 16
   SCRIPT_OUTPUT       = 32
   @@index             = Hash.new
   @@streams           = Hash.new
   @@mutex             = Mutex.new
   @@offset            = 0
   @@buffer            = Array.new
   @@max_size          = 3000
   def Buffer.gets
      thread_id = Thread.current.object_id
      if @@index[thread_id].nil?
         @@mutex.synchronize {
            @@index[thread_id] = (@@offset + @@buffer.length)
            @@streams[thread_id] ||= DOWNSTREAM_STRIPPED
         }
      end
      line = nil
      loop {
         if (@@index[thread_id] - @@offset) >= @@buffer.length
            sleep 0.05 while ((@@index[thread_id] - @@offset) >= @@buffer.length)
         end
         @@mutex.synchronize {
            if @@index[thread_id] < @@offset
               @@index[thread_id] = @@offset
            end
            line = @@buffer[@@index[thread_id] - @@offset]
         }
         @@index[thread_id] += 1
         break if ((line.stream & @@streams[thread_id]) != 0)
      }
      return line
   end
   def Buffer.gets?
      thread_id = Thread.current.object_id
      if @@index[thread_id].nil?
         @@mutex.synchronize {
            @@index[thread_id] = (@@offset + @@buffer.length)
            @@streams[thread_id] ||= DOWNSTREAM_STRIPPED
         }
      end
      line = nil
      loop {
         if (@@index[thread_id] - @@offset) >= @@buffer.length
            return nil
         end
         @@mutex.synchronize {
            if @@index[thread_id] < @@offset
               @@index[thread_id] = @@offset
            end
            line = @@buffer[@@index[thread_id] - @@offset]
         }
         @@index[thread_id] += 1
         break if ((line.stream & @@streams[thread_id]) != 0)
      }
      return line
   end
   def Buffer.rewind
      thread_id = Thread.current.object_id
      @@index[thread_id] = @@offset
      @@streams[thread_id] ||= DOWNSTREAM_STRIPPED
      return self
   end
   def Buffer.clear
      thread_id = Thread.current.object_id
      if @@index[thread_id].nil?
         @@mutex.synchronize {
            @@index[thread_id] = (@@offset + @@buffer.length)
            @@streams[thread_id] ||= DOWNSTREAM_STRIPPED
         }
      end
      lines = Array.new
      loop {
         if (@@index[thread_id] - @@offset) >= @@buffer.length
            return lines
         end
         line = nil
         @@mutex.synchronize {
            if @@index[thread_id] < @@offset
               @@index[thread_id] = @@offset
            end
            line = @@buffer[@@index[thread_id] - @@offset]
         }
         @@index[thread_id] += 1
         lines.push(line) if ((line.stream & @@streams[thread_id]) != 0)
      }
      return lines
   end
   def Buffer.update(line, stream=nil)
      @@mutex.synchronize {
         frozen_line = line.dup
         unless stream.nil?
            frozen_line.stream = stream
         end
         frozen_line.freeze
         @@buffer.push(frozen_line)
         while (@@buffer.length > @@max_size)
            @@buffer.shift
            @@offset += 1
         end
      }
      return self
   end
   def Buffer.streams
      @@streams[Thread.current.object_id]
   end
   def Buffer.streams=(val)
      if (val.class != Fixnum) or ((val & 63) == 0)
         respond "--- Lich: error: invalid streams value\n\t#{$!.caller[0..2].join("\n\t")}"
         return nil
      end
      @@streams[Thread.current.object_id] = val
   end
   def Buffer.cleanup
      @@index.delete_if { |k,v| not Thread.list.any? { |t| t.object_id == k } }
      @@streams.delete_if { |k,v| not Thread.list.any? { |t| t.object_id == k } }
      return self
   end
end

class SharedBuffer
   attr_accessor :max_size
   def initialize(args={})
      @buffer = Array.new
      @buffer_offset = 0
      @buffer_index = Hash.new
      @buffer_mutex = Mutex.new
      @max_size = args[:max_size] || 500
      return self
   end
   def gets
      thread_id = Thread.current.object_id
      if @buffer_index[thread_id].nil?
         @buffer_mutex.synchronize { @buffer_index[thread_id] = (@buffer_offset + @buffer.length) }
      end
      if (@buffer_index[thread_id] - @buffer_offset) >= @buffer.length
         sleep 0.05 while ((@buffer_index[thread_id] - @buffer_offset) >= @buffer.length)
      end
      line = nil
      @buffer_mutex.synchronize {
         if @buffer_index[thread_id] < @buffer_offset
            @buffer_index[thread_id] = @buffer_offset
         end
         line = @buffer[@buffer_index[thread_id] - @buffer_offset]
      }
      @buffer_index[thread_id] += 1
      return line
   end
   def gets?
      thread_id = Thread.current.object_id
      if @buffer_index[thread_id].nil?
         @buffer_mutex.synchronize { @buffer_index[thread_id] = (@buffer_offset + @buffer.length) }
      end
      if (@buffer_index[thread_id] - @buffer_offset) >= @buffer.length
         return nil
      end
      line = nil
      @buffer_mutex.synchronize {
         if @buffer_index[thread_id] < @buffer_offset
            @buffer_index[thread_id] = @buffer_offset
         end
         line = @buffer[@buffer_index[thread_id] - @buffer_offset]
      }
      @buffer_index[thread_id] += 1
      return line
   end
   def clear
      thread_id = Thread.current.object_id
      if @buffer_index[thread_id].nil?
         @buffer_mutex.synchronize { @buffer_index[thread_id] = (@buffer_offset + @buffer.length) }
         return Array.new
      end
      if (@buffer_index[thread_id] - @buffer_offset) >= @buffer.length
         return Array.new
      end
      lines = Array.new
      @buffer_mutex.synchronize {
         if @buffer_index[thread_id] < @buffer_offset
            @buffer_index[thread_id] = @buffer_offset
         end
         lines = @buffer[(@buffer_index[thread_id] - @buffer_offset)..-1]
         @buffer_index[thread_id] = (@buffer_offset + @buffer.length)
      }
      return lines
   end
   def rewind
      @buffer_index[Thread.current.object_id] = @buffer_offset
      return self
   end
   def update(line)
      @buffer_mutex.synchronize {
         fline = line.dup
         fline.freeze
         @buffer.push(fline)
         while (@buffer.length > @max_size)
            @buffer.shift
            @buffer_offset += 1
         end
      }
      return self
   end
   def cleanup_threads
      @buffer_index.delete_if { |k,v| not Thread.list.any? { |t| t.object_id == k } }
      return self
   end
end

class SpellRanks
   @@list      ||= Array.new
   @@timestamp ||= 0
   @@loaded    ||= false
   @@elevated_load = proc { SpellRanks.load }
   @@elevated_save = proc { SpellRanks.save }
   attr_reader :name
   attr_accessor :minorspiritual, :majorspiritual, :cleric, :minorelemental, :majorelemental, :minormental, :ranger, :sorcerer, :wizard, :bard, :empath, :paladin, :arcanesymbols, :magicitemuse, :monk
   def SpellRanks.load
      if $SAFE == 0
         if File.exists?("#{DATA_DIR}/#{XMLData.game}/spell-ranks.dat")
            begin
               File.open("#{DATA_DIR}/#{XMLData.game}/spell-ranks.dat", 'rb') { |f|
                  @@timestamp, @@list = Marshal.load(f.read)
               }
               # minor mental circle added 2012-07-18; old data files will have @minormental as nil
               @@list.each { |rank_info| rank_info.minormental ||= 0 }
               # monk circle added 2013-01-15; old data files will have @minormental as nil
               @@list.each { |rank_info| rank_info.monk ||= 0 }
               @@loaded = true
            rescue
               respond "--- Lich: error: SpellRanks.load: #{$!}"
               Lich.log "error: SpellRanks.load: #{$!}\n\t#{$!.backtrace.join("\n\t")}"
               @@list      = Array.new
               @@timestamp = 0
               @@loaded = true
            end
         else
            @@loaded = true
         end
      else
         @@elevated_load.call
      end
   end
   def SpellRanks.save
      if $SAFE == 0
         begin
            File.open("#{DATA_DIR}/#{XMLData.game}/spell-ranks.dat", 'wb') { |f|
               f.write(Marshal.dump([@@timestamp, @@list]))
            }
         rescue
            respond "--- Lich: error: SpellRanks.save: #{$!}"
            Lich.log "error: SpellRanks.save: #{$!}\n\t#{$!.backtrace.join("\n\t")}"
         end
      else
         @@elevated_save.call
      end
   end
   def SpellRanks.timestamp
      SpellRanks.load unless @@loaded
      @@timestamp
   end
   def SpellRanks.timestamp=(val)
      SpellRanks.load unless @@loaded
      @@timestamp = val
   end
   def SpellRanks.[](name)
      SpellRanks.load unless @@loaded
      @@list.find { |n| n.name == name }
   end
   def SpellRanks.list
      SpellRanks.load unless @@loaded
      @@list
   end
   def SpellRanks.method_missing(arg=nil)
      echo "error: unknown method #{arg} for class SpellRanks"
      respond caller[0..1]
   end
   def initialize(name)
      SpellRanks.load unless @@loaded
      @name = name
      @minorspiritual, @majorspiritual, @cleric, @minorelemental, @majorelemental, @ranger, @sorcerer, @wizard, @bard, @empath, @paladin, @minormental, @arcanesymbols, @magicitemuse = 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0
      @@list.push(self)
   end
end


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
                           $_CLIENT_.write(alt_string)
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
                           stripped_server.split("\r\n").each { |line|
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
      
      class Char
         @@name ||= nil
         @@citizenship ||= nil
         private_class_method :new
         def Char.init(blah)
            echo 'Char.init is no longer used.  Update or fix your script.'
         end
         def Char.name
            XMLData.name
         end
         def Char.name=(name)
            nil
         end
         def Char.health(*args)
            health(*args)
         end
         def Char.mana(*args)
            checkmana(*args)
         end
         def Char.spirit(*args)
            checkspirit(*args)
         end
         def Char.maxhealth
            Object.module_eval { maxhealth }
         end
         def Char.maxmana
            Object.module_eval { maxmana }
         end
         def Char.maxspirit
            Object.module_eval { maxspirit }
         end
         def Char.stamina(*args)
            checkstamina(*args)
         end
         def Char.maxstamina
            Object.module_eval { maxstamina }
         end
         def Char.cha(val=nil)
            nil
         end
         def Char.dump_info
            Marshal.dump([
               Spell.detailed?,
               Spell.serialize,
               Spellsong.serialize,
               Stats.serialize,
               Skills.serialize,
               Spells.serialize,
               Gift.serialize,
               Society.serialize,
            ])
         end
         def Char.load_info(string)
            save = Char.dump_info
            begin
               Spell.load_detailed,
               Spell.load_active,
               Spellsong.load_serialized,
               Stats.load_serialized,
               Skills.load_serialized,
               Spells.load_serialized,
               Gift.load_serialized,
               Society.load_serialized = Marshal.load(string)
            rescue
               raise $! if string == save
               string = save
               retry
            end
         end
         def Char.method_missing(meth, *args)
            [ Stats, Skills, Spellsong, Society ].each { |klass|
               begin
                  result = klass.__send__(meth, *args)
                  return result
               rescue
               end
            }
            respond 'missing method: ' + meth
            raise NoMethodError
         end
         def Char.info
            ary = []
            ary.push sprintf("Name: %s  Race: %s  Profession: %s", XMLData.name, Stats.race, Stats.prof)
            ary.push sprintf("Gender: %s    Age: %d    Expr: %d    Level: %d", Stats.gender, Stats.age, Stats.exp, Stats.level)
            ary.push sprintf("%017.17s Normal (Bonus)  ...  Enhanced (Bonus)", "")
            %w[ Strength Constitution Dexterity Agility Discipline Aura Logic Intuition Wisdom Influence ].each { |stat|
               val, bon = Stats.send(stat[0..2].downcase)
               spc = " " * (4 - bon.to_s.length)
               ary.push sprintf("%012s (%s): %05s (%d) %s ... %05s (%d)", stat, stat[0..2].upcase, val, bon, spc, val, bon)
            }
            ary.push sprintf("Mana: %04s", mana)
            ary
         end
         def Char.skills
            ary = []
            ary.push sprintf("%s (at level %d), your current skill bonuses and ranks (including all modifiers) are:", XMLData.name, Stats.level)
            ary.push sprintf("  %-035s| Current Current", 'Skill Name')
            ary.push sprintf("  %-035s|%08s%08s", '', 'Bonus', 'Ranks')
            fmt = [ [ 'Two Weapon Combat', 'Armor Use', 'Shield Use', 'Combat Maneuvers', 'Edged Weapons', 'Blunt Weapons', 'Two-Handed Weapons', 'Ranged Weapons', 'Thrown Weapons', 'Polearm Weapons', 'Brawling', 'Ambush', 'Multi Opponent Combat', 'Combat Leadership', 'Physical Fitness', 'Dodging', 'Arcane Symbols', 'Magic Item Use', 'Spell Aiming', 'Harness Power', 'Elemental Mana Control', 'Mental Mana Control', 'Spirit Mana Control', 'Elemental Lore - Air', 'Elemental Lore - Earth', 'Elemental Lore - Fire', 'Elemental Lore - Water', 'Spiritual Lore - Blessings', 'Spiritual Lore - Religion', 'Spiritual Lore - Summoning', 'Sorcerous Lore - Demonology', 'Sorcerous Lore - Necromancy', 'Mental Lore - Divination', 'Mental Lore - Manipulation', 'Mental Lore - Telepathy', 'Mental Lore - Transference', 'Mental Lore - Transformation', 'Survival', 'Disarming Traps', 'Picking Locks', 'Stalking and Hiding', 'Perception', 'Climbing', 'Swimming', 'First Aid', 'Trading', 'Pickpocketing' ], [ 'twoweaponcombat', 'armoruse', 'shielduse', 'combatmaneuvers', 'edgedweapons', 'bluntweapons', 'twohandedweapons', 'rangedweapons', 'thrownweapons', 'polearmweapons', 'brawling', 'ambush', 'multiopponentcombat', 'combatleadership', 'physicalfitness', 'dodging', 'arcanesymbols', 'magicitemuse', 'spellaiming', 'harnesspower', 'emc', 'mmc', 'smc', 'elair', 'elearth', 'elfire', 'elwater', 'slblessings', 'slreligion', 'slsummoning', 'sldemonology', 'slnecromancy', 'mldivination', 'mlmanipulation', 'mltelepathy', 'mltransference', 'mltransformation', 'survival', 'disarmingtraps', 'pickinglocks', 'stalkingandhiding', 'perception', 'climbing', 'swimming', 'firstaid', 'trading', 'pickpocketing' ] ]
            0.upto(fmt.first.length - 1) { |n|
               dots = '.' * (35 - fmt[0][n].length)
               rnk = Skills.send(fmt[1][n])
               ary.push sprintf("  %s%s|%08s%08s", fmt[0][n], dots, Skills.to_bonus(rnk), rnk) unless rnk.zero?
            }
            %[Minor Elemental,Major Elemental,Minor Spirit,Major Spirit,Minor Mental,Bard,Cleric,Empath,Paladin,Ranger,Sorcerer,Wizard].split(',').each { |circ|
               rnk = Spells.send(circ.gsub(" ", '').downcase)
               if rnk.nonzero?
                  ary.push ''
                  ary.push "Spell Lists"
                  dots = '.' * (35 - circ.length)
                  ary.push sprintf("  %s%s|%016s", circ, dots, rnk)
               end
            }
            ary
         end
         def Char.citizenship
            @@citizenship
         end
         def Char.citizenship=(val)
            @@citizenship = val.to_s
         end
      end

      class Society
         @@status ||= String.new
         @@rank ||= 0
         def Society.serialize
            [@@status,@@rank]
         end
         def Society.load_serialized=(val)
            @@status,@@rank = val
         end
         def Society.status=(val)
            @@status = val
         end
         def Society.status
            @@status.dup
         end
         def Society.rank=(val)
            if val =~ /Master/
               if @@status =~ /Voln/
                  @@rank = 26
               elsif @@status =~ /Council of Light|Guardians of Sunfist/
                  @@rank = 20
               else
                  @@rank = val.to_i
               end
            else
               @@rank = val.slice(/[0-9]+/).to_i
            end
         end
         def Society.step
            @@rank
         end
         def Society.member
            @@status.dup
         end
         def Society.rank
            @@rank
         end
         def Society.task
            XMLData.society_task
         end
      end

      class Spellsong
         @@renewed ||= Time.at(Time.now.to_i - 1200)
         def Spellsong.renewed
            @@renewed = Time.now
         end
         def Spellsong.renewed=(val)
            @@renewed = val
         end
         def Spellsong.renewed_at
            @@renewed
         end
         def Spellsong.timeleft
            (Spellsong.duration - ((Time.now - @@renewed) % Spellsong.duration)) / 60.to_f
         end
         def Spellsong.serialize
            Spellsong.timeleft
         end
         def Spellsong.load_serialized=(old)
            Thread.new {
               n = 0
               while Stats.level == 0
                  sleep 0.25
                  n += 1
                  break if n >= 4
               end
               unless n >= 4
                  @@renewed = Time.at(Time.now.to_f - (Spellsong.duration - old * 60.to_f))
               else
                  @@renewed = Time.now
               end
            }
            nil
         end
         def Spellsong.duration
            total = 120
            1.upto(Stats.level.to_i) { |n|
               if n < 26
                  total += 4
               elsif n < 51
                  total += 3
               elsif n < 76
                  total += 2
               else
                  total += 1
               end
            }
            total + Stats.log[1].to_i + (Stats.inf[1].to_i * 3) + (Skills.mltelepathy.to_i * 2)
         end
         def Spellsong.renew_cost
            # fixme: multi-spell penalty?
            total = num_active = 0
            [ 1003, 1006, 1009, 1010, 1012, 1014, 1018, 1019, 1025 ].each { |song_num|
               if song = Spell[song_num]
                  if song.active?
                     total += song.renew_cost
                     num_active += 1
                  end
               else
                  echo "Spellsong.renew_cost: warning: can't find song number #{song_num}"
               end
            }
            return total
         end
         def Spellsong.sonicarmordurability
            210 + (Stats.level / 2).round + Skills.to_bonus(Skills.elair)
         end
         def Spellsong.sonicbladedurability
            160 + (Stats.level / 2).round + Skills.to_bonus(Skills.elair)
         end
         def Spellsong.sonicweapondurability
            Spellsong.sonicbladedurability
         end
         def Spellsong.sonicshielddurability
            125 + (Stats.level / 2).round + Skills.to_bonus(Skills.elair)
         end
         def Spellsong.tonishastebonus
            bonus = -1
            thresholds = [30,75]
            thresholds.each { |val| if Skills.elair >= val then bonus -= 1 end }
            bonus
         end
         def Spellsong.depressionpushdown
            20 + Skills.mltelepathy
         end
         def Spellsong.depressionslow
            thresholds = [10,25,45,70,100]
            bonus = -2
            thresholds.each { |val| if Skills.mltelepathy >= val then bonus -= 1 end }
            bonus
         end
         def Spellsong.holdingtargets
            1 + ((Spells.bard - 1) / 7).truncate
         end
      end

      class Skills
         @@twoweaponcombat ||= 0
         @@armoruse ||= 0
         @@shielduse ||= 0
         @@combatmaneuvers ||= 0
         @@edgedweapons ||= 0
         @@bluntweapons ||= 0
         @@twohandedweapons ||= 0
         @@rangedweapons ||= 0
         @@thrownweapons ||= 0
         @@polearmweapons ||= 0
         @@brawling ||= 0
         @@ambush ||= 0
         @@multiopponentcombat ||= 0
         @@combatleadership ||= 0
         @@physicalfitness ||= 0
         @@dodging ||= 0
         @@arcanesymbols ||= 0
         @@magicitemuse ||= 0
         @@spellaiming ||= 0
         @@harnesspower ||= 0
         @@emc ||= 0
         @@mmc ||= 0
         @@smc ||= 0
         @@elair ||= 0
         @@elearth ||= 0
         @@elfire ||= 0
         @@elwater ||= 0
         @@slblessings ||= 0
         @@slreligion ||= 0
         @@slsummoning ||= 0
         @@sldemonology ||= 0
         @@slnecromancy ||= 0
         @@mldivination ||= 0
         @@mlmanipulation ||= 0
         @@mltelepathy ||= 0
         @@mltransference ||= 0
         @@mltransformation ||= 0
         @@survival ||= 0
         @@disarmingtraps ||= 0
         @@pickinglocks ||= 0
         @@stalkingandhiding ||= 0
         @@perception ||= 0
         @@climbing ||= 0
         @@swimming ||= 0
         @@firstaid ||= 0
         @@trading ||= 0
         @@pickpocketing ||= 0

         def Skills.twoweaponcombat;           @@twoweaponcombat;         end
         def Skills.twoweaponcombat=(val);     @@twoweaponcombat=val;     end
         def Skills.armoruse;                  @@armoruse;                end
         def Skills.armoruse=(val);            @@armoruse=val;            end
         def Skills.shielduse;                 @@shielduse;               end
         def Skills.shielduse=(val);           @@shielduse=val;           end
         def Skills.combatmaneuvers;           @@combatmaneuvers;         end
         def Skills.combatmaneuvers=(val);     @@combatmaneuvers=val;     end
         def Skills.edgedweapons;              @@edgedweapons;            end
         def Skills.edgedweapons=(val);        @@edgedweapons=val;        end
         def Skills.bluntweapons;              @@bluntweapons;            end
         def Skills.bluntweapons=(val);        @@bluntweapons=val;        end
         def Skills.twohandedweapons;          @@twohandedweapons;        end
         def Skills.twohandedweapons=(val);    @@twohandedweapons=val;    end
         def Skills.rangedweapons;             @@rangedweapons;           end
         def Skills.rangedweapons=(val);       @@rangedweapons=val;       end
         def Skills.thrownweapons;             @@thrownweapons;           end
         def Skills.thrownweapons=(val);       @@thrownweapons=val;       end
         def Skills.polearmweapons;            @@polearmweapons;          end
         def Skills.polearmweapons=(val);      @@polearmweapons=val;      end
         def Skills.brawling;                  @@brawling;                end
         def Skills.brawling=(val);            @@brawling=val;            end
         def Skills.ambush;                    @@ambush;                  end
         def Skills.ambush=(val);              @@ambush=val;              end
         def Skills.multiopponentcombat;       @@multiopponentcombat;     end
         def Skills.multiopponentcombat=(val); @@multiopponentcombat=val; end
         def Skills.combatleadership;          @@combatleadership;        end
         def Skills.combatleadership=(val);    @@combatleadership=val;    end
         def Skills.physicalfitness;           @@physicalfitness;         end
         def Skills.physicalfitness=(val);     @@physicalfitness=val;     end
         def Skills.dodging;                   @@dodging;                 end
         def Skills.dodging=(val);             @@dodging=val;             end
         def Skills.arcanesymbols;             @@arcanesymbols;           end
         def Skills.arcanesymbols=(val);       @@arcanesymbols=val;       end
         def Skills.magicitemuse;              @@magicitemuse;            end
         def Skills.magicitemuse=(val);        @@magicitemuse=val;        end
         def Skills.spellaiming;               @@spellaiming;             end
         def Skills.spellaiming=(val);         @@spellaiming=val;         end
         def Skills.harnesspower;              @@harnesspower;            end
         def Skills.harnesspower=(val);        @@harnesspower=val;        end
         def Skills.emc;                       @@emc;                     end
         def Skills.emc=(val);                 @@emc=val;                 end
         def Skills.mmc;                       @@mmc;                     end
         def Skills.mmc=(val);                 @@mmc=val;                 end
         def Skills.smc;                       @@smc;                     end
         def Skills.smc=(val);                 @@smc=val;                 end
         def Skills.elair;                     @@elair;                   end
         def Skills.elair=(val);               @@elair=val;               end
         def Skills.elearth;                   @@elearth;                 end
         def Skills.elearth=(val);             @@elearth=val;             end
         def Skills.elfire;                    @@elfire;                  end
         def Skills.elfire=(val);              @@elfire=val;              end
         def Skills.elwater;                   @@elwater;                 end
         def Skills.elwater=(val);             @@elwater=val;             end
         def Skills.slblessings;               @@slblessings;             end
         def Skills.slblessings=(val);         @@slblessings=val;         end
         def Skills.slreligion;                @@slreligion;              end
         def Skills.slreligion=(val);          @@slreligion=val;          end
         def Skills.slsummoning;               @@slsummoning;             end
         def Skills.slsummoning=(val);         @@slsummoning=val;         end
         def Skills.sldemonology;              @@sldemonology;            end
         def Skills.sldemonology=(val);        @@sldemonology=val;        end
         def Skills.slnecromancy;              @@slnecromancy;            end
         def Skills.slnecromancy=(val);        @@slnecromancy=val;        end
         def Skills.mldivination;              @@mldivination;            end
         def Skills.mldivination=(val);        @@mldivination=val;        end
         def Skills.mlmanipulation;            @@mlmanipulation;          end
         def Skills.mlmanipulation=(val);      @@mlmanipulation=val;      end
         def Skills.mltelepathy;               @@mltelepathy;             end
         def Skills.mltelepathy=(val);         @@mltelepathy=val;         end
         def Skills.mltransference;            @@mltransference;          end
         def Skills.mltransference=(val);      @@mltransference=val;      end
         def Skills.mltransformation;          @@mltransformation;        end
         def Skills.mltransformation=(val);    @@mltransformation=val;    end
         def Skills.survival;                  @@survival;                end
         def Skills.survival=(val);            @@survival=val;            end
         def Skills.disarmingtraps;            @@disarmingtraps;          end
         def Skills.disarmingtraps=(val);      @@disarmingtraps=val;      end
         def Skills.pickinglocks;              @@pickinglocks;            end
         def Skills.pickinglocks=(val);        @@pickinglocks=val;        end
         def Skills.stalkingandhiding;         @@stalkingandhiding;       end
         def Skills.stalkingandhiding=(val);   @@stalkingandhiding=val;   end
         def Skills.perception;                @@perception;              end
         def Skills.perception=(val);          @@perception=val;          end
         def Skills.climbing;                  @@climbing;                end
         def Skills.climbing=(val);            @@climbing=val;            end
         def Skills.swimming;                  @@swimming;                end
         def Skills.swimming=(val);            @@swimming=val;            end
         def Skills.firstaid;                  @@firstaid;                end
         def Skills.firstaid=(val);            @@firstaid=val;            end
         def Skills.trading;                   @@trading;                 end
         def Skills.trading=(val);             @@trading=val;             end
         def Skills.pickpocketing;             @@pickpocketing;           end
         def Skills.pickpocketing=(val);       @@pickpocketing=val;       end

         def Skills.serialize
            [@@twoweaponcombat, @@armoruse, @@shielduse, @@combatmaneuvers, @@edgedweapons, @@bluntweapons, @@twohandedweapons, @@rangedweapons, @@thrownweapons, @@polearmweapons, @@brawling, @@ambush, @@multiopponentcombat, @@combatleadership, @@physicalfitness, @@dodging, @@arcanesymbols, @@magicitemuse, @@spellaiming, @@harnesspower, @@emc, @@mmc, @@smc, @@elair, @@elearth, @@elfire, @@elwater, @@slblessings, @@slreligion, @@slsummoning, @@sldemonology, @@slnecromancy, @@mldivination, @@mlmanipulation, @@mltelepathy, @@mltransference, @@mltransformation, @@survival, @@disarmingtraps, @@pickinglocks, @@stalkingandhiding, @@perception, @@climbing, @@swimming, @@firstaid, @@trading, @@pickpocketing]
         end
         def Skills.load_serialized=(array)
            @@twoweaponcombat, @@armoruse, @@shielduse, @@combatmaneuvers, @@edgedweapons, @@bluntweapons, @@twohandedweapons, @@rangedweapons, @@thrownweapons, @@polearmweapons, @@brawling, @@ambush, @@multiopponentcombat, @@combatleadership, @@physicalfitness, @@dodging, @@arcanesymbols, @@magicitemuse, @@spellaiming, @@harnesspower, @@emc, @@mmc, @@smc, @@elair, @@elearth, @@elfire, @@elwater, @@slblessings, @@slreligion, @@slsummoning, @@sldemonology, @@slnecromancy, @@mldivination, @@mlmanipulation, @@mltelepathy, @@mltransference, @@mltransformation, @@survival, @@disarmingtraps, @@pickinglocks, @@stalkingandhiding, @@perception, @@climbing, @@swimming, @@firstaid, @@trading, @@pickpocketing = array
         end
         def Skills.to_bonus(ranks)
            bonus = 0
            while ranks > 0
               if ranks > 40
                  bonus += (ranks - 40)
                  ranks = 40
               elsif ranks > 30
                  bonus += (ranks - 30) * 2
                  ranks = 30
               elsif ranks > 20
                  bonus += (ranks - 20) * 3
                  ranks = 20
               elsif ranks > 10
                  bonus += (ranks - 10) * 4
                  ranks = 10
               else
                  bonus += (ranks * 5)
                  ranks = 0
               end
            end
            bonus
         end
      end

      class Spells
         @@minorelemental ||= 0
         @@minormental    ||= 0
         @@majorelemental ||= 0
         @@minorspiritual ||= 0
         @@majorspiritual ||= 0
         @@wizard         ||= 0
         @@sorcerer       ||= 0
         @@ranger         ||= 0
         @@paladin        ||= 0
         @@empath         ||= 0
         @@cleric         ||= 0
         @@bard           ||= 0
         def Spells.minorelemental=(val); @@minorelemental = val; end
         def Spells.minorelemental;       @@minorelemental;       end
         def Spells.minormental=(val);    @@minormental = val;    end
         def Spells.minormental;          @@minormental;          end
         def Spells.majorelemental=(val); @@majorelemental = val; end
         def Spells.majorelemental;       @@majorelemental;       end
         def Spells.minorspiritual=(val); @@minorspiritual = val; end
         def Spells.minorspiritual;       @@minorspiritual;       end
         def Spells.minorspirit=(val);    @@minorspiritual = val; end
         def Spells.minorspirit;          @@minorspiritual;       end
         def Spells.majorspiritual=(val); @@majorspiritual = val; end
         def Spells.majorspiritual;       @@majorspiritual;       end
         def Spells.majorspirit=(val);    @@majorspiritual = val; end
         def Spells.majorspirit;          @@majorspiritual;       end
         def Spells.wizard=(val);         @@wizard = val;         end
         def Spells.wizard;               @@wizard;               end
         def Spells.sorcerer=(val);       @@sorcerer = val;       end
         def Spells.sorcerer;             @@sorcerer;             end
         def Spells.ranger=(val);         @@ranger = val;         end
         def Spells.ranger;               @@ranger;               end
         def Spells.paladin=(val);        @@paladin = val;        end
         def Spells.paladin;              @@paladin;              end
         def Spells.empath=(val);         @@empath = val;         end
         def Spells.empath;               @@empath;               end
         def Spells.cleric=(val);         @@cleric = val;         end
         def Spells.cleric;               @@cleric;               end
         def Spells.bard=(val);           @@bard = val;           end
         def Spells.bard;                 @@bard;                 end
         def Spells.get_circle_name(num)
            val = num.to_s
            if val == '1'
               'Minor Spirit'
            elsif val == '2'
               'Major Spirit'
            elsif val == '3'
               'Cleric'
            elsif val == '4'
               'Minor Elemental'
            elsif val == '5'
               'Major Elemental'
            elsif val == '6'
               'Ranger'
            elsif val == '7'
               'Sorcerer'
            elsif val == '9'
               'Wizard'
            elsif val == '10'
               'Bard'
            elsif val == '11'
               'Empath'
            elsif val == '12'
               'Minor Mental'
            elsif val == '16'
               'Paladin'
            elsif val == '17'
               'Arcane'
            elsif val == '66'
               'Death'
            elsif val == '65'
               'Imbedded Enchantment'
            elsif val == '90'
               'Miscellaneous'
            elsif val == '95'
               'Armor Specialization'
            elsif val == '96'
               'Combat Maneuvers'
            elsif val == '97'
               'Guardians of Sunfist'
            elsif val == '98'
               'Order of Voln'
            elsif val == '99'
               'Council of Light'
            else
               'Unknown Circle'
            end
         end
         def Spells.active
            Spell.active
         end
         def Spells.known
            known_spells = Array.new
            Spell.list.each { |spell| known_spells.push(spell) if spell.known? }
            return known_spells
         end
         def Spells.serialize
            [@@minorelemental,@@majorelemental,@@minorspiritual,@@majorspiritual,@@wizard,@@sorcerer,@@ranger,@@paladin,@@empath,@@cleric,@@bard,@@minormental]
         end
         def Spells.load_serialized=(val)
            @@minorelemental,@@majorelemental,@@minorspiritual,@@majorspiritual,@@wizard,@@sorcerer,@@ranger,@@paladin,@@empath,@@cleric,@@bard,@@minormental = val
            # new spell circle added 2012-07-18; old data files will make @@minormental nil
            @@minormental ||= 0
         end
      end

      require_relative("./lib/spell")

      class CMan
         @@armor_spike_focus      ||= 0
         @@bearhug                ||= 0
         @@berserk                ||= 0
         @@block_mastery          ||= 0
         @@bull_rush              ||= 0
         @@burst_of_swiftness     ||= 0
         @@charge                 ||= 0
         @@cheapshots             ||= 0
         @@combat_focus           ||= 0
         @@combat_mastery         ||= 0
         @@combat_mobility        ||= 0
         @@combat_movement        ||= 0
         @@combat_toughness       ||= 0
         @@coup_de_grace          ||= 0
         @@crowd_press            ||= 0
         @@cunning_defense        ||= 0
         @@cutthroat              ||= 0
         @@dirtkick               ||= 0
         @@disarm_weapon          ||= 0
         @@divert                 ||= 0
         @@duck_and_weave         ||= 0
         @@dust_shroud            ||= 0
         @@evade_mastery          ||= 0
         @@executioners_stance    ||= 0
         @@feint                  ||= 0
         @@flurry_of_blows        ||= 0
         @@garrote                ||= 0
         @@grapple_mastery        ||= 0
         @@griffins_voice         ||= 0
         @@groin_kick             ||= 0
         @@hamstring              ||= 0
         @@haymaker               ||= 0
         @@headbutt               ||= 0
         @@inner_harmony          ||= 0
         @@internal_power         ||= 0
         @@ki_focus               ||= 0
         @@kick_mastery           ||= 0
         @@mighty_blow            ||= 0
         @@multi_fire             ||= 0
         @@mystic_strike          ||= 0
         @@parry_mastery          ||= 0
         @@perfect_self           ||= 0
         @@precision              ||= 0
         @@predators_eye          ||= 0
         @@punch_mastery          ||= 0
         @@quickstrike            ||= 0
         @@rolling_krynch_stance  ||= 0
         @@shadow_mastery         ||= 0
         @@shield_bash            ||= 0
         @@shield_charge          ||= 0
         @@side_by_side           ||= 0
         @@silent_strike          ||= 0
         @@slippery_mind          ||= 0
         @@specialization_i       ||= 0
         @@specialization_ii      ||= 0
         @@specialization_iii     ||= 0
         @@spell_cleaving         ||= 0
         @@spell_parry            ||= 0
         @@spell_thieve           ||= 0
         @@spin_attack            ||= 0
         @@staggering_blow        ||= 0
         @@stance_of_the_mongoose ||= 0
         @@striking_asp           ||= 0
         @@stun_maneuvers         ||= 0
         @@subdual_strike         ||= 0
         @@subdue                 ||= 0
         @@sucker_punch           ||= 0
         @@sunder_shield          ||= 0
         @@surge_of_strength      ||= 0
         @@sweep                  ||= 0
         @@tackle                 ||= 0
         @@tainted_bond           ||= 0
         @@trip                   ||= 0
         @@truehand               ||= 0
         @@twin_hammerfists       ||= 0
         @@unarmed_specialist     ||= 0
         @@weapon_bonding         ||= 0
         @@vanish                 ||= 0
         @@whirling_dervish       ||= 0

         def CMan.armor_spike_focus;        @@armor_spike_focus;      end
         def CMan.bearhug;                  @@bearhug;                end
         def CMan.berserk;                  @@berserk;                end
         def CMan.block_mastery;            @@block_mastery;          end
         def CMan.bull_rush;                @@bull_rush;              end
         def CMan.burst_of_swiftness;       @@burst_of_swiftness;     end
         def CMan.charge;                   @@charge;                 end
         def CMan.cheapshots;               @@cheapshots;             end
         def CMan.combat_focus;             @@combat_focus;           end
         def CMan.combat_mastery;           @@combat_mastery;         end
         def CMan.combat_mobility;          @@combat_mobility;        end
         def CMan.combat_movement;          @@combat_movement;        end
         def CMan.combat_toughness;         @@combat_toughness;       end
         def CMan.coup_de_grace;            @@coup_de_grace;          end
         def CMan.crowd_press;              @@crowd_press;            end
         def CMan.cunning_defense;          @@cunning_defense;        end
         def CMan.cutthroat;                @@cutthroat;              end
         def CMan.dirtkick;                 @@dirtkick;               end
         def CMan.disarm_weapon;            @@disarm_weapon;          end
         def CMan.divert;                   @@divert;                 end
         def CMan.duck_and_weave;           @@duck_and_weave;         end
         def CMan.dust_shroud;              @@dust_shroud;            end
         def CMan.evade_mastery;            @@evade_mastery;          end
         def CMan.executioners_stance;      @@executioners_stance;    end
         def CMan.feint;                    @@feint;                  end
         def CMan.flurry_of_blows;          @@flurry_of_blows;        end
         def CMan.garrote;                  @@garrote;                end
         def CMan.grapple_mastery;          @@grapple_mastery;        end
         def CMan.griffins_voice;           @@griffins_voice;         end
         def CMan.groin_kick;               @@groin_kick;             end
         def CMan.hamstring;                @@hamstring;              end
         def CMan.haymaker;                 @@haymaker;               end
         def CMan.headbutt;                 @@headbutt;               end
         def CMan.inner_harmony;            @@inner_harmony;          end
         def CMan.internal_power;           @@internal_power;         end
         def CMan.ki_focus;                 @@ki_focus;               end
         def CMan.kick_mastery;             @@kick_mastery;           end
         def CMan.mighty_blow;              @@mighty_blow;            end
         def CMan.multi_fire;               @@multi_fire;             end
         def CMan.mystic_strike;            @@mystic_strike;          end
         def CMan.parry_mastery;            @@parry_mastery;          end
         def CMan.perfect_self;             @@perfect_self;           end
         def CMan.precision;                @@precision;              end
         def CMan.predators_eye;            @@predators_eye;          end
         def CMan.punch_mastery;            @@punch_mastery;          end
         def CMan.quickstrike;              @@quickstrike;            end
         def CMan.rolling_krynch_stance;    @@rolling_krynch_stance;  end
         def CMan.shadow_mastery;           @@shadow_mastery;         end
         def CMan.shield_bash;              @@shield_bash;            end
         def CMan.shield_charge;            @@shield_charge;          end
         def CMan.side_by_side;             @@side_by_side;           end
         def CMan.silent_strike;            @@silent_strike;          end
         def CMan.slippery_mind;            @@slippery_mind;          end
         def CMan.specialization_i;         @@specialization_i;       end
         def CMan.specialization_ii;        @@specialization_ii;      end
         def CMan.specialization_iii;       @@specialization_iii;     end
         def CMan.spell_cleaving;           @@spell_cleaving;         end
         def CMan.spell_parry;              @@spell_parry;            end
         def CMan.spell_thieve;             @@spell_thieve;           end
         def CMan.spin_attack;              @@spin_attack;            end
         def CMan.staggering_blow;          @@staggering_blow;        end
         def CMan.stance_of_the_mongoose;   @@stance_of_the_mongoose; end
         def CMan.striking_asp;             @@striking_asp;           end
         def CMan.stun_maneuvers;           @@stun_maneuvers;         end
         def CMan.subdual_strike;           @@subdual_strike;         end
         def CMan.subdue;                   @@subdue;                 end
         def CMan.sucker_punch;             @@sucker_punch;           end
         def CMan.sunder_shield;            @@sunder_shield;          end
         def CMan.surge_of_strength;        @@surge_of_strength;      end
         def CMan.sweep;                    @@sweep;                  end
         def CMan.tackle;                   @@tackle;                 end
         def CMan.tainted_bond;             @@tainted_bond;           end
         def CMan.trip;                     @@trip;                   end
         def CMan.truehand;                 @@truehand;               end
         def CMan.twin_hammerfists;         @@twin_hammerfists;       end
         def CMan.unarmed_specialist;       @@unarmed_specialist;     end
         def CMan.vanish;                   @@vanish;                 end
         def CMan.weapon_bonding;           @@weapon_bonding;         end
         def CMan.whirling_dervish;         @@whirling_dervish;       end

         def CMan.armor_spike_focus=(val);        @@armor_spike_focus=val;      end
         def CMan.bearhug=(val);                  @@bearhug=val;                end
         def CMan.berserk=(val);                  @@berserk=val;                end
         def CMan.block_mastery=(val);            @@block_mastery=val;          end
         def CMan.bull_rush=(val);                @@bull_rush=val;              end
         def CMan.burst_of_swiftness=(val);       @@burst_of_swiftness=val;     end
         def CMan.charge=(val);                   @@charge=val;                 end
         def CMan.cheapshots=(val);               @@cheapshots=val;             end
         def CMan.combat_focus=(val);             @@combat_focus=val;           end
         def CMan.combat_mastery=(val);           @@combat_mastery=val;         end
         def CMan.combat_mobility=(val);          @@combat_mobility=val;        end
         def CMan.combat_movement=(val);          @@combat_movement=val;        end
         def CMan.combat_toughness=(val);         @@combat_toughness=val;       end
         def CMan.coup_de_grace=(val);            @@coup_de_grace=val;          end
         def CMan.crowd_press=(val);              @@crowd_press=val;            end
         def CMan.cunning_defense=(val);          @@cunning_defense=val;        end
         def CMan.cutthroat=(val);                @@cutthroat=val;              end
         def CMan.dirtkick=(val);                 @@dirtkick=val;               end
         def CMan.disarm_weapon=(val);            @@disarm_weapon=val;          end
         def CMan.divert=(val);                   @@divert=val;                 end
         def CMan.duck_and_weave=(val);           @@duck_and_weave=val;         end
         def CMan.dust_shroud=(val);              @@dust_shroud=val;            end
         def CMan.evade_mastery=(val);            @@evade_mastery=val;          end
         def CMan.executioners_stance=(val);      @@executioners_stance=val;    end
         def CMan.feint=(val);                    @@feint=val;                  end
         def CMan.flurry_of_blows=(val);          @@flurry_of_blows=val;        end
         def CMan.garrote=(val);                  @@garrote=val;                end
         def CMan.grapple_mastery=(val);          @@grapple_mastery=val;        end
         def CMan.griffins_voice=(val);           @@griffins_voice=val;         end
         def CMan.groin_kick=(val);               @@groin_kick=val;             end
         def CMan.hamstring=(val);                @@hamstring=val;              end
         def CMan.haymaker=(val);                 @@haymaker=val;               end
         def CMan.headbutt=(val);                 @@headbutt=val;               end
         def CMan.inner_harmony=(val);            @@inner_harmony=val;          end
         def CMan.internal_power=(val);           @@internal_power=val;         end
         def CMan.ki_focus=(val);                 @@ki_focus=val;               end
         def CMan.kick_mastery=(val);             @@kick_mastery=val;           end
         def CMan.mighty_blow=(val);              @@mighty_blow=val;            end
         def CMan.multi_fire=(val);               @@multi_fire=val;             end
         def CMan.mystic_strike=(val);            @@mystic_strike=val;          end
         def CMan.parry_mastery=(val);            @@parry_mastery=val;          end
         def CMan.perfect_self=(val);             @@perfect_self=val;           end
         def CMan.precision=(val);                @@precision=val;              end
         def CMan.predators_eye=(val);            @@predators_eye=val;          end
         def CMan.punch_mastery=(val);            @@punch_mastery=val;          end
         def CMan.quickstrike=(val);              @@quickstrike=val;            end
         def CMan.rolling_krynch_stance=(val);    @@rolling_krynch_stance=val;  end
         def CMan.shadow_mastery=(val);           @@shadow_mastery=val;         end
         def CMan.shield_bash=(val);              @@shield_bash=val;            end
         def CMan.shield_charge=(val);            @@shield_charge=val;          end
         def CMan.side_by_side=(val);             @@side_by_side=val;           end
         def CMan.silent_strike=(val);            @@silent_strike=val;          end
         def CMan.slippery_mind=(val);            @@slippery_mind=val;          end
         def CMan.specialization_i=(val);         @@specialization_i=val;       end
         def CMan.specialization_ii=(val);        @@specialization_ii=val;      end
         def CMan.specialization_iii=(val);       @@specialization_iii=val;     end
         def CMan.spell_cleaving=(val);           @@spell_cleaving=val;         end
         def CMan.spell_parry=(val);              @@spell_parry=val;            end
         def CMan.spell_thieve=(val);             @@spell_thieve=val;           end
         def CMan.spin_attack=(val);              @@spin_attack=val;            end
         def CMan.staggering_blow=(val);          @@staggering_blow=val;        end
         def CMan.stance_of_the_mongoose=(val);   @@stance_of_the_mongoose=val; end
         def CMan.striking_asp=(val);             @@striking_asp=val;           end
         def CMan.stun_maneuvers=(val);           @@stun_maneuvers=val;         end
         def CMan.subdual_strike=(val);           @@subdual_strike=val;         end
         def CMan.subdue=(val);                   @@subdue=val;                 end
         def CMan.sucker_punch=(val);             @@sucker_punch=val;           end
         def CMan.sunder_shield=(val);            @@sunder_shield=val;          end
         def CMan.surge_of_strength=(val);        @@surge_of_strength=val;      end
         def CMan.sweep=(val);                    @@sweep=val;                  end
         def CMan.tackle=(val);                   @@tackle=val;                 end
         def CMan.tainted_bond=(val);             @@tainted_bond=val;           end
         def CMan.trip=(val);                     @@trip=val;                   end
         def CMan.truehand=(val);                 @@truehand=val;               end
         def CMan.twin_hammerfists=(val);         @@twin_hammerfists=val;       end
         def CMan.unarmed_specialist=(val);       @@unarmed_specialist=val;     end
         def CMan.vanish=(val);                   @@vanish=val;                 end
         def CMan.weapon_bonding=(val);           @@weapon_bonding=val;         end
         def CMan.whirling_dervish=(val);         @@whirling_dervish=val;       end

         def CMan.method_missing(arg1, arg2=nil)
            nil
         end
         def CMan.[](name)
            CMan.send(name.gsub(/[\s\-]/, '_').gsub("'", "").downcase)
         end
         def CMan.[]=(name,val)
            CMan.send("#{name.gsub(/[\s\-]/, '_').gsub("'", "").downcase}=", val.to_i)
         end
      end

      class Stats
         @@race ||= 'unknown'
         @@prof ||= 'unknown'
         @@gender ||= 'unknown'
         @@age ||= 0
         @@level ||= 0
         @@str ||= [0,0]
         @@con ||= [0,0]
         @@dex ||= [0,0]
         @@agi ||= [0,0]
         @@dis ||= [0,0]
         @@aur ||= [0,0]
         @@log ||= [0,0]
         @@int ||= [0,0]
         @@wis ||= [0,0]
         @@inf ||= [0,0]
         def Stats.race;         @@race;       end
         def Stats.race=(val);   @@race=val;   end
         def Stats.prof;         @@prof;       end
         def Stats.prof=(val);   @@prof=val;   end
         def Stats.gender;       @@gender;     end
         def Stats.gender=(val); @@gender=val; end
         def Stats.age;          @@age;        end
         def Stats.age=(val);    @@age=val;    end
         def Stats.level;        @@level;      end
         def Stats.level=(val);  @@level=val;  end
         def Stats.str;          @@str;        end
         def Stats.str=(val);    @@str=val;    end
         def Stats.con;          @@con;        end
         def Stats.con=(val);    @@con=val;    end
         def Stats.dex;          @@dex;        end
         def Stats.dex=(val);    @@dex=val;    end
         def Stats.agi;          @@agi;        end
         def Stats.agi=(val);    @@agi=val;    end
         def Stats.dis;          @@dis;        end
         def Stats.dis=(val);    @@dis=val;    end
         def Stats.aur;          @@aur;        end
         def Stats.aur=(val);    @@aur=val;    end
         def Stats.log;          @@log;        end
         def Stats.log=(val);    @@log=val;    end
         def Stats.int;          @@int;        end
         def Stats.int=(val);    @@int=val;    end
         def Stats.wis;          @@wis;        end
         def Stats.wis=(val);    @@wis=val;    end
         def Stats.inf;          @@inf;        end
         def Stats.inf=(val);    @@inf=val;    end
         def Stats.exp
            if XMLData.next_level_text =~ /until next level/
               exp_threshold = [ 2500, 5000, 10000, 17500, 27500, 40000, 55000, 72500, 92500, 115000, 140000, 167000, 197500, 230000, 265000, 302000, 341000, 382000, 425000, 470000, 517000, 566000, 617000, 670000, 725000, 781500, 839500, 899000, 960000, 1022500, 1086500, 1152000, 1219000, 1287500, 1357500, 1429000, 1502000, 1576500, 1652500, 1730000, 1808500, 1888000, 1968500, 2050000, 2132500, 2216000, 2300500, 2386000, 2472500, 2560000, 2648000, 2736500, 2825500, 2915000, 3005000, 3095500, 3186500, 3278000, 3370000, 3462500, 3555500, 3649000, 3743000, 3837500, 3932500, 4028000, 4124000, 4220500, 4317500, 4415000, 4513000, 4611500, 4710500, 4810000, 4910000, 5010500, 5111500, 5213000, 5315000, 5417500, 5520500, 5624000, 5728000, 5832500, 5937500, 6043000, 6149000, 6255500, 6362500, 6470000, 6578000, 6686500, 6795500, 6905000, 7015000, 7125500, 7236500, 7348000, 7460000, 7572500 ]
               exp_threshold[XMLData.level] - XMLData.next_level_text.slice(/[0-9]+/).to_i
            else
               XMLData.next_level_text.slice(/[0-9]+/).to_i
            end
         end
         def Stats.exp=(val);    nil;    end
         def Stats.serialize
            [@@race,@@prof,@@gender,@@age,Stats.exp,@@level,@@str,@@con,@@dex,@@agi,@@dis,@@aur,@@log,@@int,@@wis,@@inf]
         end
         def Stats.load_serialized=(array)
            @@race,@@prof,@@gender,@@age = array[0..3]
            @@level,@@str,@@con,@@dex,@@agi,@@dis,@@aur,@@log,@@int,@@wis,@@inf = array[5..15]
         end
      end

      class Gift
         @@gift_start ||= Time.now
         @@pulse_count ||= 0
         def Gift.started
            @@gift_start = Time.now
            @@pulse_count = 0
         end
         def Gift.pulse
            @@pulse_count += 1
         end
         def Gift.remaining
            ([360 - @@pulse_count, 0].max * 60).to_f
         end
         def Gift.restarts_on
            @@gift_start + 594000
         end
         def Gift.serialize
            [@@gift_start, @@pulse_count]
         end
         def Gift.load_serialized=(array)
            @@gift_start = array[0]
            @@pulse_count = array[1].to_i
         end
         def Gift.ended
            @@pulse_count = 360
         end
         def Gift.stopwatch
            nil
         end
      end

      class Wounds
         def Wounds.leftEye;   fix_injury_mode; XMLData.injuries['leftEye']['wound'];   end
         def Wounds.leye;      fix_injury_mode; XMLData.injuries['leftEye']['wound'];   end
         def Wounds.rightEye;  fix_injury_mode; XMLData.injuries['rightEye']['wound'];  end
         def Wounds.reye;      fix_injury_mode; XMLData.injuries['rightEye']['wound'];  end
         def Wounds.head;      fix_injury_mode; XMLData.injuries['head']['wound'];      end
         def Wounds.neck;      fix_injury_mode; XMLData.injuries['neck']['wound'];      end
         def Wounds.back;      fix_injury_mode; XMLData.injuries['back']['wound'];      end
         def Wounds.chest;     fix_injury_mode; XMLData.injuries['chest']['wound'];     end
         def Wounds.abdomen;   fix_injury_mode; XMLData.injuries['abdomen']['wound'];   end
         def Wounds.abs;       fix_injury_mode; XMLData.injuries['abdomen']['wound'];   end
         def Wounds.leftArm;   fix_injury_mode; XMLData.injuries['leftArm']['wound'];   end
         def Wounds.larm;      fix_injury_mode; XMLData.injuries['leftArm']['wound'];   end
         def Wounds.rightArm;  fix_injury_mode; XMLData.injuries['rightArm']['wound'];  end
         def Wounds.rarm;      fix_injury_mode; XMLData.injuries['rightArm']['wound'];  end
         def Wounds.rightHand; fix_injury_mode; XMLData.injuries['rightHand']['wound']; end
         def Wounds.rhand;     fix_injury_mode; XMLData.injuries['rightHand']['wound']; end
         def Wounds.leftHand;  fix_injury_mode; XMLData.injuries['leftHand']['wound'];  end
         def Wounds.lhand;     fix_injury_mode; XMLData.injuries['leftHand']['wound'];  end
         def Wounds.leftLeg;   fix_injury_mode; XMLData.injuries['leftLeg']['wound'];   end
         def Wounds.lleg;      fix_injury_mode; XMLData.injuries['leftLeg']['wound'];   end
         def Wounds.rightLeg;  fix_injury_mode; XMLData.injuries['rightLeg']['wound'];  end
         def Wounds.rleg;      fix_injury_mode; XMLData.injuries['rightLeg']['wound'];  end
         def Wounds.leftFoot;  fix_injury_mode; XMLData.injuries['leftFoot']['wound'];  end
         def Wounds.rightFoot; fix_injury_mode; XMLData.injuries['rightFoot']['wound']; end
         def Wounds.nsys;      fix_injury_mode; XMLData.injuries['nsys']['wound'];      end
         def Wounds.nerves;    fix_injury_mode; XMLData.injuries['nsys']['wound'];      end
         def Wounds.arms
            fix_injury_mode
            [XMLData.injuries['leftArm']['wound'],XMLData.injuries['rightArm']['wound'],XMLData.injuries['leftHand']['wound'],XMLData.injuries['rightHand']['wound']].max
         end
         def Wounds.limbs
            fix_injury_mode
            [XMLData.injuries['leftArm']['wound'],XMLData.injuries['rightArm']['wound'],XMLData.injuries['leftHand']['wound'],XMLData.injuries['rightHand']['wound'],XMLData.injuries['leftLeg']['wound'],XMLData.injuries['rightLeg']['wound']].max
         end
         def Wounds.torso
            fix_injury_mode
            [XMLData.injuries['rightEye']['wound'],XMLData.injuries['leftEye']['wound'],XMLData.injuries['chest']['wound'],XMLData.injuries['abdomen']['wound'],XMLData.injuries['back']['wound']].max
         end
         def Wounds.method_missing(arg=nil)
            echo "Wounds: Invalid area, try one of these: arms, limbs, torso, #{XMLData.injuries.keys.join(', ')}"
            nil
         end
      end

      class Scars
         def Scars.leftEye;   fix_injury_mode; XMLData.injuries['leftEye']['scar'];   end
         def Scars.leye;      fix_injury_mode; XMLData.injuries['leftEye']['scar'];   end
         def Scars.rightEye;  fix_injury_mode; XMLData.injuries['rightEye']['scar'];  end
         def Scars.reye;      fix_injury_mode; XMLData.injuries['rightEye']['scar'];  end
         def Scars.head;      fix_injury_mode; XMLData.injuries['head']['scar'];      end
         def Scars.neck;      fix_injury_mode; XMLData.injuries['neck']['scar'];      end
         def Scars.back;      fix_injury_mode; XMLData.injuries['back']['scar'];      end
         def Scars.chest;     fix_injury_mode; XMLData.injuries['chest']['scar'];     end
         def Scars.abdomen;   fix_injury_mode; XMLData.injuries['abdomen']['scar'];   end
         def Scars.abs;       fix_injury_mode; XMLData.injuries['abdomen']['scar'];   end
         def Scars.leftArm;   fix_injury_mode; XMLData.injuries['leftArm']['scar'];   end
         def Scars.larm;      fix_injury_mode; XMLData.injuries['leftArm']['scar'];   end
         def Scars.rightArm;  fix_injury_mode; XMLData.injuries['rightArm']['scar'];  end
         def Scars.rarm;      fix_injury_mode; XMLData.injuries['rightArm']['scar'];  end
         def Scars.rightHand; fix_injury_mode; XMLData.injuries['rightHand']['scar']; end
         def Scars.rhand;     fix_injury_mode; XMLData.injuries['rightHand']['scar']; end
         def Scars.leftHand;  fix_injury_mode; XMLData.injuries['leftHand']['scar'];  end
         def Scars.lhand;     fix_injury_mode; XMLData.injuries['leftHand']['scar'];  end
         def Scars.leftLeg;   fix_injury_mode; XMLData.injuries['leftLeg']['scar'];   end
         def Scars.lleg;      fix_injury_mode; XMLData.injuries['leftLeg']['scar'];   end
         def Scars.rightLeg;  fix_injury_mode; XMLData.injuries['rightLeg']['scar'];  end
         def Scars.rleg;      fix_injury_mode; XMLData.injuries['rightLeg']['scar'];  end
         def Scars.leftFoot;  fix_injury_mode; XMLData.injuries['leftFoot']['scar'];  end
         def Scars.rightFoot; fix_injury_mode; XMLData.injuries['rightFoot']['scar']; end
         def Scars.nsys;      fix_injury_mode; XMLData.injuries['nsys']['scar'];      end
         def Scars.nerves;    fix_injury_mode; XMLData.injuries['nsys']['scar'];      end
         def Scars.arms
            fix_injury_mode
            [XMLData.injuries['leftArm']['scar'],XMLData.injuries['rightArm']['scar'],XMLData.injuries['leftHand']['scar'],XMLData.injuries['rightHand']['scar']].max
         end
         def Scars.limbs
            fix_injury_mode
            [XMLData.injuries['leftArm']['scar'],XMLData.injuries['rightArm']['scar'],XMLData.injuries['leftHand']['scar'],XMLData.injuries['rightHand']['scar'],XMLData.injuries['leftLeg']['scar'],XMLData.injuries['rightLeg']['scar']].max
         end
         def Scars.torso
            fix_injury_mode
            [XMLData.injuries['rightEye']['scar'],XMLData.injuries['leftEye']['scar'],XMLData.injuries['chest']['scar'],XMLData.injuries['abdomen']['scar'],XMLData.injuries['back']['scar']].max
         end
         def Scars.method_missing(arg=nil)
            echo "Scars: Invalid area, try one of these: arms, limbs, torso, #{XMLData.injuries.keys.join(', ')}"
            nil
         end
      end
      class GameObj
         @@loot          = Array.new
         @@npcs          = Array.new
         @@npc_status    = Hash.new
         @@pcs           = Array.new
         @@pc_status     = Hash.new
         @@inv           = Array.new
         @@contents      = Hash.new
         @@right_hand    = nil
         @@left_hand     = nil
         @@room_desc     = Array.new
         @@fam_loot      = Array.new
         @@fam_npcs      = Array.new
         @@fam_pcs       = Array.new
         @@fam_room_desc = Array.new
         @@type_data     = Hash.new
         @@sellable_data = Hash.new
         @@elevated_load = proc { GameObj.load_data }

         attr_reader :id
         attr_accessor :noun, :name, :before_name, :after_name
         def initialize(id, noun, name, before=nil, after=nil)
            @id = id
            @noun = noun
            @noun = 'lapis' if @noun == 'lapis lazuli'
            @noun = 'hammer' if @noun == "Hammer of Kai"
            @noun = 'mother-of-pearl' if (@noun == 'pearl') and (@name =~ /mother\-of\-pearl/)
            @name = name
            @before_name = before
            @after_name = after
         end
         def type
            GameObj.load_data if @@type_data.empty?
            list = @@type_data.keys.find_all { |t| (@name =~ @@type_data[t][:name] or @noun =~ @@type_data[t][:noun]) and (@@type_data[t][:exclude].nil? or @name !~ @@type_data[t][:exclude]) }
            if list.empty?
               nil
            else
               list.join(',')
            end
         end
         def sellable
            GameObj.load_data if @@sellable_data.empty?
            list = @@sellable_data.keys.find_all { |t| (@name =~ @@sellable_data[t][:name] or @noun =~ @@sellable_data[t][:noun]) and (@@sellable_data[t][:exclude].nil? or @name !~ @@sellable_data[t][:exclude]) }
            if list.empty?
               nil
            else
               list.join(',')
            end
         end
         def status
            if @@npc_status.keys.include?(@id)
               @@npc_status[@id]
            elsif @@pc_status.keys.include?(@id)
               @@pc_status[@id]
            elsif @@loot.find { |obj| obj.id == @id } or @@inv.find { |obj| obj.id == @id } or @@room_desc.find { |obj| obj.id == @id } or @@fam_loot.find { |obj| obj.id == @id } or @@fam_npcs.find { |obj| obj.id == @id } or @@fam_pcs.find { |obj| obj.id == @id } or @@fam_room_desc.find { |obj| obj.id == @id } or (@@right_hand.id == @id) or (@@left_hand.id == @id) or @@contents.values.find { |list| list.find { |obj| obj.id == @id  } }
               nil
            else
               'gone'
            end
         end
         def status=(val)
            if @@npcs.any? { |npc| npc.id == @id }
               @@npc_status[@id] = val
            elsif @@pcs.any? { |pc| pc.id == @id }
               @@pc_status[@id] = val
            else
               nil
            end
         end
         def to_s
            @noun
         end
         def empty?
            false
         end
         def contents
            @@contents[@id].dup
         end
         def GameObj.[](val)
            if val.class == String
               if val =~ /^\-?[0-9]+$/
                  obj = @@inv.find { |o| o.id == val } || @@loot.find { |o| o.id == val } || @@npcs.find { |o| o.id == val } || @@pcs.find { |o| o.id == val } || [ @@right_hand, @@left_hand ].find { |o| o.id == val } || @@room_desc.find { |o| o.id == val }
               elsif val.split(' ').length == 1
                  obj = @@inv.find { |o| o.noun == val } || @@loot.find { |o| o.noun == val } || @@npcs.find { |o| o.noun == val } || @@pcs.find { |o| o.noun == val } || [ @@right_hand, @@left_hand ].find { |o| o.noun == val } || @@room_desc.find { |o| o.noun == val }
               else
                  obj = @@inv.find { |o| o.name == val } || @@loot.find { |o| o.name == val } || @@npcs.find { |o| o.name == val } || @@pcs.find { |o| o.name == val } || [ @@right_hand, @@left_hand ].find { |o| o.name == val } || @@room_desc.find { |o| o.name == val } || @@inv.find { |o| o.name =~ /\b#{Regexp.escape(val.strip)}$/i } || @@loot.find { |o| o.name =~ /\b#{Regexp.escape(val.strip)}$/i } || @@npcs.find { |o| o.name =~ /\b#{Regexp.escape(val.strip)}$/i } || @@pcs.find { |o| o.name =~ /\b#{Regexp.escape(val.strip)}$/i } || [ @@right_hand, @@left_hand ].find { |o| o.name =~ /\b#{Regexp.escape(val.strip)}$/i } || @@room_desc.find { |o| o.name =~ /\b#{Regexp.escape(val.strip)}$/i } || @@inv.find { |o| o.name =~ /\b#{Regexp.escape(val).sub(' ', ' .*')}$/i } || @@loot.find { |o| o.name =~ /\b#{Regexp.escape(val).sub(' ', ' .*')}$/i } || @@npcs.find { |o| o.name =~ /\b#{Regexp.escape(val).sub(' ', ' .*')}$/i } || @@pcs.find { |o| o.name =~ /\b#{Regexp.escape(val).sub(' ', ' .*')}$/i } || [ @@right_hand, @@left_hand ].find { |o| o.name =~ /\b#{Regexp.escape(val).sub(' ', ' .*')}$/i } || @@room_desc.find { |o| o.name =~ /\b#{Regexp.escape(val).sub(' ', ' .*')}$/i }
               end
            elsif val.class == Regexp
               obj = @@inv.find { |o| o.name =~ val } || @@loot.find { |o| o.name =~ val } || @@npcs.find { |o| o.name =~ val } || @@pcs.find { |o| o.name =~ val } || [ @@right_hand, @@left_hand ].find { |o| o.name =~ val } || @@room_desc.find { |o| o.name =~ val }
            end
         end
         def GameObj
            @noun
         end
         def full_name
            "#{@before_name}#{' ' unless @before_name.nil? or @before_name.empty?}#{name}#{' ' unless @after_name.nil? or @after_name.empty?}#{@after_name}"
         end
         def GameObj.new_npc(id, noun, name, status=nil)
            obj = GameObj.new(id, noun, name)
            @@npcs.push(obj)
            @@npc_status[id] = status
            obj
         end
         def GameObj.new_loot(id, noun, name)
            obj = GameObj.new(id, noun, name)
            @@loot.push(obj)
            obj
         end
         def GameObj.new_pc(id, noun, name, status=nil)
            obj = GameObj.new(id, noun, name)
            @@pcs.push(obj)
            @@pc_status[id] = status
            obj
         end
         def GameObj.new_inv(id, noun, name, container=nil, before=nil, after=nil)
            obj = GameObj.new(id, noun, name, before, after)
            if container
               @@contents[container].push(obj)
            else
               @@inv.push(obj)
            end
            obj
         end
         def GameObj.new_room_desc(id, noun, name)
            obj = GameObj.new(id, noun, name)
            @@room_desc.push(obj)
            obj
         end
         def GameObj.new_fam_room_desc(id, noun, name)
            obj = GameObj.new(id, noun, name)
            @@fam_room_desc.push(obj)
            obj
         end
         def GameObj.new_fam_loot(id, noun, name)
            obj = GameObj.new(id, noun, name)
            @@fam_loot.push(obj)
            obj
         end
         def GameObj.new_fam_npc(id, noun, name)
            obj = GameObj.new(id, noun, name)
            @@fam_npcs.push(obj)
            obj
         end
         def GameObj.new_fam_pc(id, noun, name)
            obj = GameObj.new(id, noun, name)
            @@fam_pcs.push(obj)
            obj
         end
         def GameObj.new_right_hand(id, noun, name)
            @@right_hand = GameObj.new(id, noun, name)
         end
         def GameObj.right_hand
            @@right_hand.dup
         end
         def GameObj.new_left_hand(id, noun, name)
            @@left_hand = GameObj.new(id, noun, name)
         end
         def GameObj.left_hand
            @@left_hand.dup
         end
         def GameObj.clear_loot
            @@loot.clear
         end
         def GameObj.clear_npcs
            @@npcs.clear
            @@npc_status.clear
         end
         def GameObj.clear_pcs
            @@pcs.clear
            @@pc_status.clear
         end
         def GameObj.clear_inv
            @@inv.clear
         end
         def GameObj.clear_room_desc
            @@room_desc.clear
         end
         def GameObj.clear_fam_room_desc
            @@fam_room_desc.clear
         end
         def GameObj.clear_fam_loot
            @@fam_loot.clear
         end
         def GameObj.clear_fam_npcs
            @@fam_npcs.clear
         end
         def GameObj.clear_fam_pcs
            @@fam_pcs.clear
         end
         def GameObj.npcs
            if @@npcs.empty?
               nil
            else
               @@npcs.dup
            end
         end
         def GameObj.loot
            if @@loot.empty?
               nil
            else
               @@loot.dup
            end
         end
         def GameObj.pcs
            if @@pcs.empty?
               nil
            else
               @@pcs.dup
            end
         end
         def GameObj.inv
            if @@inv.empty?
               nil
            else
               @@inv.dup
            end
         end
         def GameObj.room_desc
            if @@room_desc.empty?
               nil
            else
               @@room_desc.dup
            end
         end
         def GameObj.fam_room_desc
            if @@fam_room_desc.empty?
               nil
            else
               @@fam_room_desc.dup
            end
         end
         def GameObj.fam_loot
            if @@fam_loot.empty?
               nil
            else
               @@fam_loot.dup
            end
         end
         def GameObj.fam_npcs
            if @@fam_npcs.empty?
               nil
            else
               @@fam_npcs.dup
            end
         end
         def GameObj.fam_pcs
            if @@fam_pcs.empty?
               nil
            else
               @@fam_pcs.dup
            end
         end
         def GameObj.clear_container(container_id)
            @@contents[container_id] = Array.new
         end
         def GameObj.delete_container(container_id)
            @@contents.delete(container_id)
         end
         def GameObj.targets
            @@npcs.select { |n| XMLData.current_target_ids.include?(n.id) }
         end
         def GameObj.dead
            dead_list = Array.new
            for obj in @@npcs
               dead_list.push(obj) if obj.status == "dead"
            end
            return nil if dead_list.empty?
            return dead_list
         end
         def GameObj.containers
            @@contents.dup
         end
         def GameObj.load_data(filename=nil)
            if $SAFE == 0
               if filename.nil?
                  if File.exists?("#{DATA_DIR}/gameobj-data.xml")
                     filename = "#{DATA_DIR}/gameobj-data.xml"
                  elsif File.exists?("#{SCRIPT_DIR}/gameobj-data.xml") # deprecated
                     filename = "#{SCRIPT_DIR}/gameobj-data.xml"
                  else
                     filename = "#{DATA_DIR}/gameobj-data.xml"
                  end
               end
               if File.exists?(filename)
                  begin
                     @@type_data = Hash.new
                     @@sellable_data = Hash.new
                     File.open(filename) { |file|
                        doc = REXML::Document.new(file.read)
                        doc.elements.each('data/type') { |e|
                           if type = e.attributes['name']
                              @@type_data[type] = Hash.new
                              @@type_data[type][:name]    = Regexp.new(e.elements['name'].text) unless e.elements['name'].text.nil? or e.elements['name'].text.empty?
                              @@type_data[type][:noun]    = Regexp.new(e.elements['noun'].text) unless e.elements['noun'].text.nil? or e.elements['noun'].text.empty?
                              @@type_data[type][:exclude] = Regexp.new(e.elements['exclude'].text) unless e.elements['exclude'].text.nil? or e.elements['exclude'].text.empty?
                           end
                        }
                        doc.elements.each('data/sellable') { |e|
                           if sellable = e.attributes['name']
                              @@sellable_data[sellable] = Hash.new
                              @@sellable_data[sellable][:name]    = Regexp.new(e.elements['name'].text) unless e.elements['name'].text.nil? or e.elements['name'].text.empty?
                              @@sellable_data[sellable][:noun]    = Regexp.new(e.elements['noun'].text) unless e.elements['noun'].text.nil? or e.elements['noun'].text.empty?
                              @@sellable_data[sellable][:exclude] = Regexp.new(e.elements['exclude'].text) unless e.elements['exclude'].text.nil? or e.elements['exclude'].text.empty?
                           end
                        }
                     }
                     true
                  rescue
                     @@type_data = nil
                     @@sellable_data = nil
                     echo "error: GameObj.load_data: #{$!}"
                     respond $!.backtrace[0..1]
                     false
                  end
               else
                  @@type_data = nil
                  @@sellable_data = nil
                  echo "error: GameObj.load_data: file does not exist: #{filename}"
                  false
               end
            else
               @@elevated_load.call
            end
         end
         def GameObj.type_data
            @@type_data
         end
         def GameObj.sellable_data
            @@sellable_data
         end
      end
      #
      # start deprecated stuff
      #
      class RoomObj < GameObj
      end
      #
      # end deprecated stuff
      #
   end
   module DragonRealms
      # fixme
   end
end

include Games::Gemstone

DIRMAP = {
   'out' => 'K',
   'ne' => 'B',
   'se' => 'D',
   'sw' => 'F',
   'nw' => 'H',
   'up' => 'I',
   'down' => 'J',
   'n' => 'A',
   'e' => 'C',
   's' => 'E',
   'w' => 'G',
}
SHORTDIR = {
   'out' => 'out',
   'northeast' => 'ne',
   'southeast' => 'se',
   'southwest' => 'sw',
   'northwest' => 'nw',
   'up' => 'up',
   'down' => 'down',
   'north' => 'n',
   'east' => 'e',
   'south' => 's',
   'west' => 'w',
}
LONGDIR = {
   'out' => 'out',
   'ne' => 'northeast',
   'se' => 'southeast',
   'sw' => 'southwest',
   'nw' => 'northwest',
   'up' => 'up',
   'down' => 'down',
   'n' => 'north',
   'e' => 'east',
   's' => 'south',
   'w' => 'west',
}
MINDMAP = {
   'clear as a bell' => 'A',
   'fresh and clear' => 'B',
   'clear' => 'C',
   'muddled' => 'D',
   'becoming numbed' => 'E',
   'numbed' => 'F',
   'must rest' => 'G',
   'saturated' => 'H',
}
ICONMAP = {
   'IconKNEELING' => 'GH',
   'IconPRONE' => 'G',
   'IconSITTING' => 'H',
   'IconSTANDING' => 'T',
   'IconSTUNNED' => 'I',
   'IconHIDDEN' => 'N',
   'IconINVISIBLE' => 'D',
   'IconDEAD' => 'B',
   'IconWEBBED' => 'C',
   'IconJOINED' => 'P',
   'IconBLEEDING' => 'O',
}

XMLData = XMLParser.new

reconnect_if_wanted = proc {
   if ARGV.include?('--reconnect') and ARGV.include?('--login') and not $_CLIENTBUFFER_.any? { |cmd| cmd =~ /^(?:\[.*?\])?(?:<c>)?(?:quit|exit)/i }
      if reconnect_arg = ARGV.find { |arg| arg =~ /^\-\-reconnect\-delay=[0-9]+(?:\+[0-9]+)?$/ }
         reconnect_arg =~ /^\-\-reconnect\-delay=([0-9]+)(\+[0-9]+)?/
         reconnect_delay = $1.to_i
         reconnect_step = $2.to_i
      else
         reconnect_delay = 60
         reconnect_step = 0
      end
      Lich.log "info: waiting #{reconnect_delay} seconds to reconnect..."
      sleep reconnect_delay
      Lich.log 'info: reconnecting...'
      if (RUBY_PLATFORM =~ /mingw|win/i) and (RUBY_PLATFORM !~ /darwin/i)
         if $frontend == 'stormfront'
            system 'taskkill /FI "WINDOWTITLE eq [GSIV: ' + Char.name + '*"' # fixme: window title changing to Gemstone IV: Char.name # name optional
         end
         args = [ 'start rubyw.exe' ]
      else
         args = [ 'ruby' ]
      end
      args.push $PROGRAM_NAME.slice(/[^\\\/]+$/)
      args.concat ARGV
      args.push '--reconnected' unless args.include?('--reconnected')
      if reconnect_step > 0
         args.delete(reconnect_arg)
         args.concat ["--reconnect-delay=#{reconnect_delay+reconnect_step}+#{reconnect_step}"]
      end
      Lich.log "exec args.join(' '): exec #{args.join(' ')}"
      exec args.join(' ')
   end
}

#
# Start deprecated stuff
#
$version = LICH_VERSION
$room_count = 0
$stormfront = true

class Spellsong
   def Spellsong.cost
      Spellsong.renew_cost
   end
   def Spellsong.tonisdodgebonus
      thresholds = [1,2,3,5,8,10,14,17,21,26,31,36,42,49,55,63,70,78,87,96]
      bonus = 20
      thresholds.each { |val| if Skills.elair >= val then bonus += 1 end }
      bonus
   end
   def Spellsong.mirrorsdodgebonus
      20 + ((Spells.bard - 19) / 2).round
   end
   def Spellsong.mirrorscost
      [19 + ((Spells.bard - 19) / 5).truncate, 8 + ((Spells.bard - 19) / 10).truncate]
   end
   def Spellsong.sonicbonus
      (Spells.bard / 2).round
   end
   def Spellsong.sonicarmorbonus
      Spellsong.sonicbonus + 15
   end
   def Spellsong.sonicbladebonus
      Spellsong.sonicbonus + 10
   end
   def Spellsong.sonicweaponbonus
      Spellsong.sonicbladebonus
   end
   def Spellsong.sonicshieldbonus
      Spellsong.sonicbonus + 10
   end
   def Spellsong.valorbonus
      10 + (([Spells.bard, Stats.level].min - 10) / 2).round
   end
   def Spellsong.valorcost
      [10 + (Spellsong.valorbonus / 2), 3 + (Spellsong.valorbonus / 5)]
   end
   def Spellsong.luckcost
      [6 + ((Spells.bard - 6) / 4),(6 + ((Spells.bard - 6) / 4) / 2).round]
   end
   def Spellsong.manacost
      [18,15]
   end
   def Spellsong.fortcost
      [3,1]
   end
   def Spellsong.shieldcost
      [9,4]
   end
   def Spellsong.weaponcost
      [12,4]
   end
   def Spellsong.armorcost
      [14,5]
   end
   def Spellsong.swordcost
      [25,15]
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


def before_dying(&code); Script.at_exit(&code); end

require_relative("./lib/settings")

module GameSettings
   def GameSettings.load; end
   def GameSettings.save; end
   def GameSettings.save_all; end
   def GameSettings.clear; end
   def GameSettings.auto=(val); end
   def GameSettings.auto; end
   def GameSettings.autoload; end
end

module CharSettings
   def CharSettings.load; end
   def CharSettings.save; end
   def CharSettings.save_all; end
   def CharSettings.clear; end
   def CharSettings.auto=(val); end
   def CharSettings.auto; end
   def CharSettings.autoload; end
end

module UserVars
   def UserVars.list
      Vars.list
   end
   def UserVars.method_missing(arg1, arg2='')
      Vars.method_missing(arg1, arg2)
   end
   def UserVars.change(var_name, value, t=nil)
      Vars[var_name] = value
   end
   def UserVars.add(var_name, value, t=nil)
      Vars[var_name] = Vars[var_name].split(', ').push(value).join(', ')
   end
   def UserVars.delete(var_name, t=nil)
      Vars[var_name] = nil
   end
   def UserVars.list_global
      Array.new
   end
   def UserVars.list_char
      Vars.list
   end
end

module Setting
   def Setting.[](name)
      Settings[name]
   end
   def Setting.[]=(name, value)
      Settings[name] = value
   end
   def Setting.to_hash(scope=':')
      Settings.to_hash
   end
end

module GameSetting
   def GameSetting.[](name)
      GameSettings[name]
   end
   def GameSetting.[]=(name, value)
      GameSettings[name] = value
   end
   def GameSetting.to_hash(scope=':')
      GameSettings.to_hash
   end
end

module CharSetting
   def CharSetting.[](name)
      CharSettings[name]
   end
   def CharSetting.[]=(name, value)
      CharSettings[name] = value
   end
   def CharSetting.to_hash(scope=':')
      CharSettings.to_hash
   end
end

class StringProc
   def StringProc._load(string)
      StringProc.new(string)
   end
end

class String
   def to_a # for compatibility with Ruby 1.8
      [self]
   end
   def silent
      false
   end
   def split_as_list
      string = self
      string.sub!(/^You (?:also see|notice) |^In the .+ you see /, ',')
      string.sub('.','').sub(/ and (an?|some|the)/, ', \1').split(',').reject { |str| str.strip.empty? }.collect { |str| str.lstrip }
   end
end

# method aliases for legacy APIs
require_relative("./lib/aliases.rb")

#
# Program start
#

ARGV.delete_if { |arg| arg =~ /launcher\.exe/i } # added by Simutronics Game Entry

argv_options = Hash.new
bad_args = Array.new

for arg in ARGV
   if (arg == '-h') or (arg == '--help')
      puts "
   -h, --help               Display this message and exit
   -v, --version            Display version number and credits and exit

   --home=<directory>      Set home directory for Lich (default: location of this file)
   --scripts=<directory>   Set directory for script files (default: home/scripts)
   --data=<directory>      Set directory for data files (default: home/data)
   --temp=<directory>      Set directory for temp files (default: home/temp)
   --logs=<directory>      Set directory for log files (default: home/logs)
   --maps=<directory>      Set directory for map images (default: home/maps)
   --backup=<directory>    Set directory for backups (default: home/backup)

   --start-scripts=<script1,script2,etc>   Start the specified scripts after login

"
      exit
   elsif (arg == '-v') or (arg == '--version')
      puts "The Lich, version #{LICH_VERSION}"
      puts ' (an implementation of the Ruby interpreter by Yukihiro Matsumoto designed to be a \'script engine\' for text-based MUDs)'
      puts ''
      puts '- The Lich program and all material collectively referred to as "The Lich project" is copyright (C) 2005-2006 Murray Miron.'
      puts '- The Gemstone IV and DragonRealms games are copyright (C) Simutronics Corporation.'
      puts '- The Wizard front-end and the StormFront front-end are also copyrighted by the Simutronics Corporation.'
      puts '- Ruby is (C) Yukihiro \'Matz\' Matsumoto.'
      puts ''
      puts 'Thanks to all those who\'ve reported bugs and helped me track down problems on both Windows and Linux.'
      exit
   elsif arg == '--link-to-sge'
      result = Lich.link_to_sge
      if $stdout.isatty
         if result
            $stdout.puts "Successfully linked to SGE."
         else
            $stdout.puts "Failed to link to SGE."
         end
      end
      exit
   elsif arg == '--unlink-from-sge'
      result = Lich.unlink_from_sge
      if $stdout.isatty
         if result
            $stdout.puts "Successfully unlinked from SGE."
         else
            $stdout.puts "Failed to unlink from SGE."
         end
      end
      exit
   elsif arg == '--link-to-sal'
      result = Lich.link_to_sal
      if $stdout.isatty
         if result
            $stdout.puts "Successfully linked to SAL files."
         else
            $stdout.puts "Failed to link to SAL files."
         end
      end
      exit
   elsif arg == '--unlink-from-sal'
      result = Lich.unlink_from_sal
      if $stdout.isatty
         if result
            $stdout.puts "Successfully unlinked from SAL files."
         else
            $stdout.puts "Failed to unlink from SAL files."
         end
      end
      exit
   elsif arg == '--install' # deprecated
      if Lich.link_to_sge and Lich.link_to_sal
         $stdout.puts 'Install was successful.'
         Lich.log 'Install was successful.'
      else
         $stdout.puts 'Install failed.'
         Lich.log 'Install failed.'
      end
      exit
   elsif arg == '--uninstall' # deprecated
      if Lich.unlink_from_sge and Lich.unlink_from_sal
         $stdout.puts 'Uninstall was successful.'
         Lich.log 'Uninstall was successful.'
      else
         $stdout.puts 'Uninstall failed.'
         Lich.log 'Uninstall failed.'
      end
      exit
   elsif arg =~ /^--(?:home)=(.+)$/i
      LICH_DIR = $1.sub(/[\\\/]$/, '')
   elsif arg =~ /^--temp=(.+)$/i
      TEMP_DIR = $1.sub(/[\\\/]$/, '')
   elsif arg =~ /^--scripts=(.+)$/i
      SCRIPT_DIR = $1.sub(/[\\\/]$/, '')
   elsif arg =~ /^--maps=(.+)$/i
      MAP_DIR = $1.sub(/[\\\/]$/, '')
   elsif arg =~ /^--logs=(.+)$/i
      LOG_DIR = $1.sub(/[\\\/]$/, '')
   elsif arg =~ /^--backup=(.+)$/i
      BACKUP_DIR = $1.sub(/[\\\/]$/, '')
   elsif arg =~ /^--data=(.+)$/i
      DATA_DIR = $1.sub(/[\\\/]$/, '')
   elsif arg =~ /^--start-scripts=(.+)$/i
      argv_options[:start_scripts] = $1
   elsif arg =~ /^--reconnect$/i
      argv_options[:reconnect] = true
   elsif arg =~ /^--reconnect-delay=(.+)$/i
      argv_options[:reconnect_delay] = $1
   elsif arg =~ /^--host=(.+):(.+)$/
      argv_options[:host] = { :domain => $1, :port => $2.to_i }
   elsif arg =~ /^--hosts-file=(.+)$/i
      argv_options[:hosts_file] = $1
   elsif arg =~ /^--gui$/i
      argv_options[:gui] = true
   elsif arg =~ /^--game=(.+)$/i
      argv_options[:game] = $1
   elsif arg =~ /^--account=(.+)$/i
      argv_options[:account] = $1
   elsif arg =~ /^--password=(.+)$/i
      argv_options[:password] = $1
   elsif arg =~ /^--character=(.+)$/i
      argv_options[:character] = $1
   elsif arg =~ /^--frontend=(.+)$/i
      argv_options[:frontend] = $1
   elsif arg =~ /^--frontend-command=(.+)$/i
      argv_options[:frontend_command] = $1
   elsif arg =~ /^--save$/i
      argv_options[:save] = true
   elsif arg =~ /^--wine(?:\-prefix)?=.+$/i
      nil # already used when defining the Wine module
   elsif arg =~ /\.sal$|Gse\.~xt$/i
      argv_options[:sal] = arg
      unless File.exists?(argv_options[:sal])
         if ARGV.join(' ') =~ /([A-Z]:\\.+?\.(?:sal|~xt))/i
            argv_options[:sal] = $1
         end
      end
      unless File.exists?(argv_options[:sal])
         if defined?(Wine)
            argv_options[:sal] = "#{Wine::PREFIX}/drive_c/#{argv_options[:sal][3..-1].split('\\').join('/')}"
         end
      end
      bad_args.clear
   else
      bad_args.push(arg)
   end
end

LICH_DIR   ||= File.dirname(File.expand_path($PROGRAM_NAME))
TEMP_DIR   ||= "#{LICH_DIR}/temp"
DATA_DIR   ||= "#{LICH_DIR}/data"
SCRIPT_DIR ||= "#{LICH_DIR}/scripts"
MAP_DIR    ||= "#{LICH_DIR}/maps"
LOG_DIR    ||= "#{LICH_DIR}/logs"
BACKUP_DIR ||= "#{LICH_DIR}/backup"

unless File.exists?(LICH_DIR)
   begin
      Dir.mkdir(LICH_DIR)
   rescue
      message = "An error occured while attempting to create directory #{LICH_DIR}\n\n"
      if not File.exists?(LICH_DIR.sub(/[\\\/]$/, '').slice(/^.+[\\\/]/).chop)
         message.concat "This was likely because the parent directory (#{LICH_DIR.sub(/[\\\/]$/, '').slice(/^.+[\\\/]/).chop}) doesn't exist."
      elsif defined?(Win32) and (Win32.GetVersionEx[:dwMajorVersion] >= 6) and (dir !~ /^[A-z]\:\\(Users|Documents and Settings)/)
         message.concat "This was likely because Lich doesn't have permission to create files and folders here.  It is recommended to put Lich in your Documents folder."
      else
         message.concat $!
      end
      Lich.msgbox(:message => message, :icon => :error)
      exit
   end
end

Dir.chdir(LICH_DIR)

unless File.exists?(TEMP_DIR)
   begin
      Dir.mkdir(TEMP_DIR)
   rescue
      message = "An error occured while attempting to create directory #{TEMP_DIR}\n\n"
      if not File.exists?(TEMP_DIR.sub(/[\\\/]$/, '').slice(/^.+[\\\/]/).chop)
         message.concat "This was likely because the parent directory (#{TEMP_DIR.sub(/[\\\/]$/, '').slice(/^.+[\\\/]/).chop}) doesn't exist."
      elsif defined?(Win32) and (Win32.GetVersionEx[:dwMajorVersion] >= 6) and (dir !~ /^[A-z]\:\\(Users|Documents and Settings)/)
         message.concat "This was likely because Lich doesn't have permission to create files and folders here.  It is recommended to put Lich in your Documents folder."
      else
         message.concat $!
      end
      Lich.msgbox(:message => message, :icon => :error)
      exit
   end
end

begin
   debug_filename = "#{TEMP_DIR}/debug-#{Time.now.strftime("%Y-%m-%d-%H-%M-%S")}.log"
   $stderr = File.open(debug_filename, 'w')
rescue
   message = "An error occured while attempting to create file #{debug_filename}\n\n"
   if defined?(Win32) and (TEMP_DIR !~ /^[A-z]\:\\(Users|Documents and Settings)/) and not Win32.isXP?
      message.concat "This was likely because Lich doesn't have permission to create files and folders here.  It is recommended to put Lich in your Documents folder."
   else
      message.concat $!
   end
   Lich.msgbox(:message => message, :icon => :error)
   exit
end

$stderr.sync = true
Lich.log "info: Lich #{LICH_VERSION}"
Lich.log "info: Ruby #{RUBY_VERSION}"
Lich.log "info: #{RUBY_PLATFORM}"

unless File.exists?(DATA_DIR)
   begin
      Dir.mkdir(DATA_DIR)   
   rescue
      Lich.log "error: #{$!}\n\t#{$!.backtrace.join("\n\t")}"
      Lich.msgbox(:message => "An error occured while attempting to create directory #{DATA_DIR}\n\n#{$!}", :icon => :error)
      exit
   end
end
unless File.exists?(SCRIPT_DIR)
   begin
      Dir.mkdir(SCRIPT_DIR)   
   rescue
      Lich.log "error: #{$!}\n\t#{$!.backtrace.join("\n\t")}"
      Lich.msgbox(:message => "An error occured while attempting to create directory #{SCRIPT_DIR}\n\n#{$!}", :icon => :error)
      exit
   end
end
unless File.exists?(MAP_DIR)
   begin
      Dir.mkdir(MAP_DIR)   
   rescue
      Lich.log "error: #{$!}\n\t#{$!.backtrace.join("\n\t")}"
      Lich.msgbox(:message => "An error occured while attempting to create directory #{MAP_DIR}\n\n#{$!}", :icon => :error)
      exit
   end
end
unless File.exists?(LOG_DIR)
   begin
      Dir.mkdir(LOG_DIR)   
   rescue
      Lich.log "error: #{$!}\n\t#{$!.backtrace.join("\n\t")}"
      Lich.msgbox(:message => "An error occured while attempting to create directory #{LOG_DIR}\n\n#{$!}", :icon => :error)
      exit
   end
end
unless File.exists?(BACKUP_DIR)
   begin
      Dir.mkdir(BACKUP_DIR)   
   rescue
      Lich.log "error: #{$!}\n\t#{$!.backtrace.join("\n\t")}"
      Lich.msgbox(:message => "An error occured while attempting to create directory #{BACKUP_DIR}\n\n#{$!}", :icon => :error)
      exit
   end
end

Lich.init_db

# deprecated
$lich_dir = "#{LICH_DIR}/"
$temp_dir = "#{TEMP_DIR}/"
$script_dir = "#{SCRIPT_DIR}/"
$data_dir = "#{DATA_DIR}/"

#
# only keep the last 20 debug files
#
Dir.entries(TEMP_DIR).find_all { |fn| fn =~ /^debug-\d+-\d+-\d+-\d+-\d+-\d+\.log$/ }.sort.reverse[20..-1].each { |oldfile|
   begin
      File.delete("#{TEMP_DIR}/#{oldfile}")
   rescue
      Lich.log "error: #{$!}\n\t#{$!.backtrace.join("\n\t")}"
   end
}

if ARGV.any? { |arg| (arg == '-h') or (arg == '--help') }
   puts 'Usage:  lich [OPTION]'
   puts ''
   puts 'Options are:'
   puts '  -h, --help          Display this list.'
   puts '  -V, --version       Display the program version number and credits.'
   puts ''
   puts '  -d, --directory     Set the main Lich program directory.'
   puts '      --script-dir    Set the directoy where Lich looks for scripts.'
   puts '      --data-dir      Set the directory where Lich will store script data.'
   puts '      --temp-dir      Set the directory where Lich will store temporary files.'
   puts ''
   puts '  -w, --wizard        Run in Wizard mode (default)'
   puts '  -s, --stormfront    Run in StormFront mode.'
   puts '      --avalon        Run in Avalon mode.'
   puts ''
   puts '      --gemstone      Connect to the Gemstone IV Prime server (default).'
   puts '      --dragonrealms  Connect to the DragonRealms server.'
   puts '      --platinum      Connect to the Gemstone IV/DragonRealms Platinum server.'
   puts '  -g, --game          Set the IP address and port of the game.  See example below.'
   puts ''
   puts '      --install       Edits the Windows/WINE registry so that Lich is started when logging in using the website or SGE.'
   puts '      --uninstall     Removes Lich from the registry.'
   puts ''
   puts 'The majority of Lich\'s built-in functionality was designed and implemented with Simutronics MUDs in mind (primarily Gemstone IV): as such, many options/features provided by Lich may not be applicable when it is used with a non-Simutronics MUD.  In nearly every aspect of the program, users who are not playing a Simutronics game should be aware that if the description of a feature/option does not sound applicable and/or compatible with the current game, it should be assumed that the feature/option is not.  This particularly applies to in-script methods (commands) that depend heavily on the data received from the game conforming to specific patterns (for instance, it\'s extremely unlikely Lich will know how much "health" your character has left in a non-Simutronics game, and so the "health" script command will most likely return a value of 0).'
   puts ''
   puts 'The level of increase in efficiency when Lich is run in "bare-bones mode" (i.e. started with the --bare argument) depends on the data stream received from a given game, but on average results in a moderate improvement and it\'s recommended that Lich be run this way for any game that does not send "status information" in a format consistent with Simutronics\' GSL or XML encoding schemas.'
   puts ''
   puts ''
   puts 'Examples:'
   puts '  lich -w -d /usr/bin/lich/          (run Lich in Wizard mode using the dir \'/usr/bin/lich/\' as the program\'s home)'
   puts '  lich -g gs3.simutronics.net:4000   (run Lich using the IP address \'gs3.simutronics.net\' and the port number \'4000\')'
   puts '  lich --script-dir /mydir/scripts   (run Lich with its script directory set to \'/mydir/scripts\')'
   puts '  lich --bare -g skotos.net:5555     (run in bare-bones mode with the IP address and port of the game set to \'skotos.net:5555\')'
   puts ''
   exit
end

if arg = ARGV.find { |a| a == '--hosts-dir' }
   i = ARGV.index(arg)
   ARGV.delete_at(i)
   hosts_dir = ARGV[i]
   ARGV.delete_at(i)
   if hosts_dir and File.exists?(hosts_dir)
      hosts_dir = hosts_dir.tr('\\', '/')
      hosts_dir += '/' unless hosts_dir[-1..-1] == '/'
   else
      $stdout.puts "warning: given hosts directory does not exist: #{hosts_dir}"
      hosts_dir = nil
   end
else
   hosts_dir = nil
end

detachable_client_port = nil
if arg = ARGV.find { |a| a =~ /^\-\-detachable\-client=[0-9]+$/ }
   detachable_client_port = /^\-\-detachable\-client=([0-9]+)$/.match(arg).captures.first
end


if argv_options[:sal]
   unless File.exists?(argv_options[:sal])
      Lich.log "error: launch file does not exist: #{argv_options[:sal]}"
      Lich.msgbox "error: launch file does not exist: #{argv_options[:sal]}"
      exit
   end
   Lich.log "info: launch file: #{argv_options[:sal]}"
   if argv_options[:sal] =~ /SGE\.sal/i
      unless launcher_cmd = Lich.get_simu_launcher
         $stdout.puts 'error: failed to find the Simutronics launcher'
         Lich.log 'error: failed to find the Simutronics launcher'
         exit
      end
      launcher_cmd.sub!('%1', argv_options[:sal])
      Lich.log "info: launcher_cmd: #{launcher_cmd}"
      if defined?(Win32) and launcher_cmd =~ /^"(.*?)"\s*(.*)$/
         dir_file = $1
         param = $2
         dir = dir_file.slice(/^.*[\\\/]/)
         file = dir_file.sub(/^.*[\\\/]/, '')
         operation = (Win32.isXP? ? 'open' : 'runas')
         Win32.ShellExecute(:lpOperation => operation, :lpFile => file, :lpDirectory => dir, :lpParameters => param)
         if r < 33
            Lich.log "error: Win32.ShellExecute returned #{r}; Win32.GetLastError: #{Win32.GetLastError}"
         end
      elsif defined?(Wine)
         system("#{Wine::BIN} #{launcher_cmd}")
      else
         system(launcher_cmd)
      end
      exit
   end
end

if arg = ARGV.find { |a| (a == '-g') or (a == '--game') }
   game_host, game_port = ARGV[ARGV.index(arg)+1].split(':')
   game_port = game_port.to_i
   if ARGV.any? { |arg| (arg == '-s') or (arg == '--stormfront') }
      $frontend = 'stormfront'
   elsif ARGV.any? { |arg| (arg == '-w') or (arg == '--wizard') }
      $frontend = 'wizard'
   elsif ARGV.any? { |arg| arg == '--avalon' }
      $frontend = 'avalon'
   else
      $frontend = 'unknown'
   end
elsif ARGV.include?('--gemstone')
   if ARGV.include?('--platinum')
      $platinum = true
      if ARGV.any? { |arg| (arg == '-s') or (arg == '--stormfront') }
         game_host = 'storm.gs4.game.play.net'
         game_port = 10124
         $frontend = 'stormfront'
      else
         game_host = 'gs-plat.simutronics.net'
         game_port = 10121
         if ARGV.any? { |arg| arg == '--avalon' }
            $frontend = 'avalon'
         else
            $frontend = 'wizard'
         end
      end
   else
      $platinum = false
      if ARGV.any? { |arg| (arg == '-s') or (arg == '--stormfront') }
         game_host = 'storm.gs4.game.play.net'
         game_port = 10024
         $frontend = 'stormfront'
      else
         game_host = 'gs3.simutronics.net'
         game_port = 4900
         if ARGV.any? { |arg| arg == '--avalon' }
            $frontend = 'avalon'
         else
            $frontend = 'wizard'
         end
      end
   end
elsif ARGV.include?('--shattered')
   $platinum = false
   if ARGV.any? { |arg| (arg == '-s') or (arg == '--stormfront') }
      game_host = 'storm.gs4.game.play.net'
      game_port = 10324
      $frontend = 'stormfront'
   else
      game_host = 'gs4.simutronics.net'
      game_port = 10321
      if ARGV.any? { |arg| arg == '--avalon' }
         $frontend = 'avalon'
      else
         $frontend = 'wizard'
      end
   end
elsif ARGV.include?('--dragonrealms')
   if ARGV.include?('--platinum')
      $platinum = true
      if ARGV.any? { |arg| (arg == '-s') or (arg == '--stormfront') }
         $stdout.puts "fixme"
         Lich.log "fixme"
         exit
         $frontend = 'stormfront'
      else
         $stdout.puts "fixme"
         Lich.log "fixme"
         exit
         $frontend = 'wizard'
      end
   else
      $platinum = false
      if ARGV.any? { |arg| (arg == '-s') or (arg == '--stormfront') }
         $frontend = 'stormfront'
         $stdout.puts "fixme"
         Lich.log "fixme"
         exit
      else
         game_host = 'dr.simutronics.net'
         game_port = 4901
         if ARGV.any? { |arg| arg == '--avalon' }
            $frontend = 'avalon'
         else
            $frontend = 'wizard'
         end
      end
   end
else
   game_host, game_port = nil, nil
   Lich.log "info: no force-mode info given"
end

main_thread = Thread.new {
          test_mode = false
    $SEND_CHARACTER = '>'
        $cmd_prefix = '<c>'
   $clean_lich_char = ';' # fixme
   $lich_char = Regexp.escape($clean_lich_char)

   launch_data = nil

   if ARGV.include?('--login')
      if File.exists?("#{DATA_DIR}/entry.dat")
         entry_data = File.open("#{DATA_DIR}/entry.dat", 'r') { |file|
            begin
               Marshal.load(file.read.unpack('m').first)
            rescue
               Array.new
            end
         }
      else
         entry_data = Array.new
      end
      char_name = ARGV[ARGV.index('--login')+1].capitalize
      if ARGV.include?('--gemstone')
         if ARGV.include?('--platinum')
            data = entry_data.find { |d| (d[:char_name] == char_name) and (d[:game_code] == 'GSX') }
         elsif ARGV.include?('--shattered')
            data = entry_data.find { |d| (d[:char_name] == char_name) and (d[:game_code] == 'GSF') }
         else
            data = entry_data.find { |d| (d[:char_name] == char_name) and (d[:game_code] == 'GS3') }
         end
      elsif ARGV.include?('--shattered')
         data = entry_data.find { |d| (d[:char_name] == char_name) and (d[:game_code] == 'GSF') }
      else
         data = entry_data.find { |d| (d[:char_name] == char_name) }
      end
      if data
         Lich.log "info: using quick game entry settings for #{char_name}"
         msgbox = proc { |msg|
            if defined?(Gtk)
               done = false
               Gtk.queue {
                  dialog = Gtk::MessageDialog.new(nil, Gtk::Dialog::DESTROY_WITH_PARENT, Gtk::MessageDialog::QUESTION, Gtk::MessageDialog::BUTTONS_CLOSE, msg)
                  dialog.run
                  dialog.destroy
                  done = true
               }
               sleep 0.1 until done
            else
               $stdout.puts(msg)
               Lich.log(msg)
            end
         }
   
         login_server = nil
         connect_thread = nil
         timeout_thread = Thread.new {
            sleep 30
            $stdout.puts "error: timed out connecting to eaccess.play.net:7900"
            Lich.log "error: timed out connecting to eaccess.play.net:7900"
            connect_thread.kill rescue nil
            login_server = nil
         }
         connect_thread = Thread.new {
            begin
               login_server = TCPSocket.new('eaccess.play.net', 7900)
            rescue
               login_server = nil
               $stdout.puts "error connecting to server: #{$!}"
               Lich.log "error connecting to server: #{$!}"
            end
         }
         connect_thread.join
         timeout_thread.kill rescue nil

         if login_server
            login_server.puts "K\n"
            hashkey = login_server.gets
            if 'test'[0].class == String
               password = data[:password].split('').collect { |c| c.getbyte(0) }
               hashkey = hashkey.split('').collect { |c| c.getbyte(0) }
            else
               password = data[:password].split('').collect { |c| c[0] }
               hashkey = hashkey.split('').collect { |c| c[0] }
            end
            password.each_index { |i| password[i] = ((password[i]-32)^hashkey[i])+32 }
            password = password.collect { |c| c.chr }.join
            login_server.puts "A\t#{data[:user_id]}\t#{password}\n"
            password = nil
            response = login_server.gets
            login_key = /KEY\t([^\t]+)\t/.match(response).captures.first
            if login_key
               login_server.puts "M\n"
               response = login_server.gets
               if response =~ /^M\t/
                  login_server.puts "F\t#{data[:game_code]}\n"
                  response = login_server.gets
                  if response =~ /NORMAL|PREMIUM|TRIAL|INTERNAL|FREE/
                     login_server.puts "G\t#{data[:game_code]}\n"
                     login_server.gets
                     login_server.puts "P\t#{data[:game_code]}\n"
                     login_server.gets
                     login_server.puts "C\n"
                     char_code = login_server.gets.sub(/^C\t[0-9]+\t[0-9]+\t[0-9]+\t[0-9]+[\t\n]/, '').scan(/[^\t]+\t[^\t^\n]+/).find { |c| c.split("\t")[1] == data[:char_name] }.split("\t")[0]
                     login_server.puts "L\t#{char_code}\tSTORM\n"
                     response = login_server.gets
                     if response =~ /^L\t/
                        login_server.close unless login_server.closed?
                        launch_data = response.sub(/^L\tOK\t/, '').split("\t")
                        if data[:frontend] == 'wizard'
                           launch_data.collect! { |line| line.sub(/GAMEFILE=.+/, 'GAMEFILE=WIZARD.EXE').sub(/GAME=.+/, 'GAME=WIZ').sub(/FULLGAMENAME=.+/, 'FULLGAMENAME=Wizard Front End') }
                        elsif data[:frontend] == 'avalon'
                           launch_data.collect! { |line| line.sub(/GAME=.+/, 'GAME=AVALON') }
                        end
                        if data[:custom_launch]
                           launch_data.push "CUSTOMLAUNCH=#{data[:custom_launch]}"
                           if data[:custom_launch_dir]
                              launch_data.push "CUSTOMLAUNCHDIR=#{data[:custom_launch_dir]}"
                           end
                        end
                     else
                        login_server.close unless login_server.closed?
                        $stdout.puts "error: unrecognized response from server. (#{response})"
                        Lich.log "error: unrecognized response from server. (#{response})"
                     end
                  else
                     login_server.close unless login_server.closed?
                     $stdout.puts "error: unrecognized response from server. (#{response})"
                     Lich.log "error: unrecognized response from server. (#{response})"
                  end
               else
                  login_server.close unless login_server.closed?
                  $stdout.puts "error: unrecognized response from server. (#{response})"
                  Lich.log "error: unrecognized response from server. (#{response})"
               end
            else
               login_server.close unless login_server.closed?
               $stdout.puts "Something went wrong... probably invalid user id and/or password.\nserver response: #{response}"
               Lich.log "Something went wrong... probably invalid user id and/or password.\nserver response: #{response}"
               reconnect_if_wanted.call
            end
         else
            $stdout.puts "error: failed to connect to server"
            Lich.log "error: failed to connect to server"
            reconnect_if_wanted.call
            Lich.log "info: exiting..."
            Gtk.queue { Gtk.main_quit } if defined?(Gtk)
            exit
         end
      else
         $stdout.puts "error: failed to find login data for #{char_name}"
         Lich.log "error: failed to find login data for #{char_name}"
      end
   elsif defined?(Gtk) and (ARGV.empty? or argv_options[:gui])
      if File.exists?("#{DATA_DIR}/entry.dat")
         entry_data = File.open("#{DATA_DIR}/entry.dat", 'r') { |file|
            begin
               Marshal.load(file.read.unpack('m').first).sort { |a,b| [a[:user_id].downcase, a[:char_name]] <=> [b[:user_id].downcase, b[:char_name]] }
            rescue
               Array.new
            end
         }
      else
         entry_data = Array.new
      end
      save_entry_data = false
      done = false
      Gtk.queue {

         login_server = nil
         window = nil
         install_tab_loaded = false

         msgbox = proc { |msg|
            dialog = Gtk::MessageDialog.new(window, Gtk::Dialog::DESTROY_WITH_PARENT, Gtk::MessageDialog::QUESTION, Gtk::MessageDialog::BUTTONS_CLOSE, msg)
            dialog.run
            dialog.destroy
         }

         #
         # quick game entry tab
         #
         if entry_data.empty?
            box = Gtk::HBox.new
            box.pack_start(Gtk::Label.new('You have no saved login info.'), true, true, 0)
            quick_game_entry_tab = Gtk::VBox.new
            quick_game_entry_tab.border_width = 5
            quick_game_entry_tab.pack_start(box, true, true, 0)
         else
            quick_box    = Gtk::VBox.new
                last_user_id = nil
            entry_data.each { |login_info|
                    if login_info[:user_id].downcase != last_user_id
                        last_user_id = login_info[:user_id].downcase
                        quick_box.pack_start(Gtk::Label.new("Account: " + last_user_id), false, false, 6)
                    end
                    
               label = Gtk::Label.new("#{login_info[:char_name]} (#{login_info[:game_name]}, #{login_info[:frontend]})")
               play_button = Gtk::Button.new('Play')
               remove_button = Gtk::Button.new('X')
               char_box = Gtk::HBox.new
               char_box.pack_start(label, false, false, 6)
               char_box.pack_end(remove_button, false, false, 0)
               char_box.pack_end(play_button, false, false, 0)
               quick_box.pack_start(char_box, false, false, 0)
               play_button.signal_connect('clicked') {
                  play_button.sensitive = false
                  begin
                     login_server = nil
                     connect_thread = Thread.new {
                        login_server = TCPSocket.new('eaccess.play.net', 7900)
                     }
                     300.times {
                        sleep 0.1
                        break unless connect_thread.status
                     }
                     if connect_thread.status
                        connect_thread.kill rescue nil
                        msgbox.call "error: timed out connecting to eaccess.play.net:7900"
                     end
                  rescue
                     msgbox.call "error connecting to server: #{$!}"
                     play_button.sensitive = true
                  end
                  if login_server
                     login_server.puts "K\n"
                     hashkey = login_server.gets
                     if 'test'[0].class == String
                        password = login_info[:password].split('').collect { |c| c.getbyte(0) }
                        hashkey = hashkey.split('').collect { |c| c.getbyte(0) }
                     else
                        password = login_info[:password].split('').collect { |c| c[0] }
                        hashkey = hashkey.split('').collect { |c| c[0] }
                     end
                     password.each_index { |i| password[i] = ((password[i]-32)^hashkey[i])+32 }
                     password = password.collect { |c| c.chr }.join
                     login_server.puts "A\t#{login_info[:user_id]}\t#{password}\n"
                     password = nil
                     response = login_server.gets
                     login_key = /KEY\t([^\t]+)\t/.match(response).captures.first
                     if login_key
                        login_server.puts "M\n"
                        response = login_server.gets
                        if response =~ /^M\t/
                           login_server.puts "F\t#{login_info[:game_code]}\n"
                           response = login_server.gets
                           if response =~ /NORMAL|PREMIUM|TRIAL|INTERNAL|FREE/
                              login_server.puts "G\t#{login_info[:game_code]}\n"
                              login_server.gets
                              login_server.puts "P\t#{login_info[:game_code]}\n"
                              login_server.gets
                              login_server.puts "C\n"
                              char_code = login_server.gets.sub(/^C\t[0-9]+\t[0-9]+\t[0-9]+\t[0-9]+[\t\n]/, '').scan(/[^\t]+\t[^\t^\n]+/).find { |c| c.split("\t")[1] == login_info[:char_name] }.split("\t")[0]
                              login_server.puts "L\t#{char_code}\tSTORM\n"
                              response = login_server.gets
                              if response =~ /^L\t/
                                 login_server.close unless login_server.closed?
                                 launch_data = response.sub(/^L\tOK\t/, '').split("\t")
                                 if login_info[:frontend] == 'wizard'
                                    launch_data.collect! { |line| line.sub(/GAMEFILE=.+/, 'GAMEFILE=WIZARD.EXE').sub(/GAME=.+/, 'GAME=WIZ').sub(/FULLGAMENAME=.+/, 'FULLGAMENAME=Wizard Front End') }
                                 end
                                 if login_info[:custom_launch]
                                    launch_data.push "CUSTOMLAUNCH=#{login_info[:custom_launch]}"
                                    if login_info[:custom_launch_dir]
                                       launch_data.push "CUSTOMLAUNCHDIR=#{login_info[:custom_launch_dir]}"
                                    end
                                 end
                                 window.destroy
                                 done = true
                              else
                                 login_server.close unless login_server.closed?
                                 msgbox.call("Unrecognized response from server. (#{response})")
                                 play_button.sensitive = true
                              end
                           else
                              login_server.close unless login_server.closed?
                              msgbox.call("Unrecognized response from server. (#{response})")
                              play_button.sensitive = true
                           end
                        else
                           login_server.close unless login_server.closed?
                           msgbox.call("Unrecognized response from server. (#{response})")
                           play_button.sensitive = true
                        end
                     else
                        login_server.close unless login_server.closed?
                        msgbox.call "Something went wrong... probably invalid user id and/or password.\nserver response: #{response}"
                        play_button.sensitive = true
                     end
                  else
                     msgbox.call "error: failed to connect to server"
                     play_button.sensitive = true
                  end
               }
               remove_button.signal_connect('clicked') {
                  entry_data.delete(login_info)
                  save_entry_data = true
                  char_box.visible = false
               }
            }

            adjustment = Gtk::Adjustment.new(0, 0, 1000, 5, 20, 500)
            quick_vp = Gtk::Viewport.new(adjustment, adjustment)
            quick_vp.add(quick_box)

            quick_sw = Gtk::ScrolledWindow.new
            quick_sw.set_policy(Gtk::POLICY_AUTOMATIC, Gtk::POLICY_ALWAYS)
            quick_sw.add(quick_vp)

            quick_game_entry_tab = Gtk::VBox.new
            quick_game_entry_tab.border_width = 5
            quick_game_entry_tab.pack_start(quick_sw, true, true, 5)
         end

         #
         # old game entry tab
         #

         user_id_entry = Gtk::Entry.new

         pass_entry = Gtk::Entry.new
         pass_entry.visibility = false

         login_table = Gtk::Table.new(2, 2, false)
         login_table.attach(Gtk::Label.new('User ID:'), 0, 1, 0, 1, Gtk::EXPAND|Gtk::FILL, Gtk::EXPAND|Gtk::FILL, 5, 5)
         login_table.attach(user_id_entry, 1, 2, 0, 1, Gtk::EXPAND|Gtk::FILL, Gtk::EXPAND|Gtk::FILL, 5, 5)
         login_table.attach(Gtk::Label.new('Password:'), 0, 1, 1, 2, Gtk::EXPAND|Gtk::FILL, Gtk::EXPAND|Gtk::FILL, 5, 5)
         login_table.attach(pass_entry, 1, 2, 1, 2, Gtk::EXPAND|Gtk::FILL, Gtk::EXPAND|Gtk::FILL, 5, 5)

         disconnect_button = Gtk::Button.new(' Disconnect ')
         disconnect_button.sensitive = false

         connect_button = Gtk::Button.new(' Connect ')

         login_button_box = Gtk::HBox.new
         login_button_box.pack_end(connect_button, false, false, 5)
         login_button_box.pack_end(disconnect_button, false, false, 5)

         liststore = Gtk::ListStore.new(String, String, String, String)
         liststore.set_sort_column_id(1, Gtk::SORT_ASCENDING)

         renderer = Gtk::CellRendererText.new


         treeview = Gtk::TreeView.new(liststore)
         treeview.height_request = 160

         col = Gtk::TreeViewColumn.new("Game", renderer, :text => 1)
         col.resizable = true
         treeview.append_column(col)

         col = Gtk::TreeViewColumn.new("Character", renderer, :text => 3)
         col.resizable = true
         treeview.append_column(col)

         sw = Gtk::ScrolledWindow.new
         sw.set_policy(Gtk::POLICY_AUTOMATIC, Gtk::POLICY_ALWAYS)
         sw.add(treeview)

         wizard_option = Gtk::RadioButton.new('Wizard')
         stormfront_option = Gtk::RadioButton.new(wizard_option, 'Stormfront')
         avalon_option = Gtk::RadioButton.new(wizard_option, 'Avalon')
         suks_option = Gtk::RadioButton.new(wizard_option, 'suks')

         frontend_box = Gtk::HBox.new(false, 10)
         frontend_box.pack_start(wizard_option, false, false, 0)
         frontend_box.pack_start(stormfront_option, false, false, 0)
         if RUBY_PLATFORM =~ /darwin/i
            frontend_box.pack_start(avalon_option, false, false, 0)
         end
         #frontend_box.pack_start(suks_option, false, false, 0)

         custom_launch_option = Gtk::CheckButton.new('Custom launch command')
         custom_launch_entry = Gtk::ComboBoxEntry.new()
         custom_launch_entry.child.text = "(enter custom launch command)"
         custom_launch_entry.append_text("Wizard.Exe /GGS /H127.0.0.1 /P%port% /K%key%")
         custom_launch_entry.append_text("Stormfront.exe /GGS/Hlocalhost/P%port%/K%key%")
         custom_launch_dir = Gtk::ComboBoxEntry.new()
         custom_launch_dir.child.text = "(enter working directory for command)"
         custom_launch_dir.append_text("../wizard")
         custom_launch_dir.append_text("../StormFront")

         make_quick_option = Gtk::CheckButton.new('Save this info for quick game entry')

         play_button = Gtk::Button.new(' Play ')
         play_button.sensitive = false

         play_button_box = Gtk::HBox.new
         play_button_box.pack_end(play_button, false, false, 5)

         game_entry_tab = Gtk::VBox.new
         game_entry_tab.border_width = 5
         game_entry_tab.pack_start(login_table, false, false, 0)
         game_entry_tab.pack_start(login_button_box, false, false, 0)
         game_entry_tab.pack_start(sw, true, true, 3)
         game_entry_tab.pack_start(frontend_box, false, false, 3)
         game_entry_tab.pack_start(custom_launch_option, false, false, 3)
         game_entry_tab.pack_start(custom_launch_entry, false, false, 3)
         game_entry_tab.pack_start(custom_launch_dir, false, false, 3)
         game_entry_tab.pack_start(make_quick_option, false, false, 3)
         game_entry_tab.pack_start(play_button_box, false, false, 3)

         custom_launch_option.signal_connect('toggled') {
            custom_launch_entry.visible = custom_launch_option.active?
            custom_launch_dir.visible = custom_launch_option.active?
         }

         avalon_option.signal_connect('toggled') {
            if avalon_option.active?
               custom_launch_option.active = false
               custom_launch_option.sensitive = false
            else
               custom_launch_option.sensitive = true
            end
         }

         connect_button.signal_connect('clicked') {
            connect_button.sensitive = false
            user_id_entry.sensitive = false
            pass_entry.sensitive = false
            iter = liststore.append
            iter[1] = 'working...'
            Gtk.queue {
               begin
                  login_server = nil
                  connect_thread = Thread.new {
                     login_server = TCPSocket.new('eaccess.play.net', 7900)
                  }
                  300.times {
                     sleep 0.1
                     break unless connect_thread.status
                  }
                  if connect_thread.status
                     connect_thread.kill rescue nil
                     msgbox.call "error: timed out connecting to eaccess.play.net:7900"
                  end
               rescue
                  msgbox.call "error connecting to server: #{$!}"
                  connect_button.sensitive = true
                  user_id_entry.sensitive = true
                  pass_entry.sensitive = true
               end
               disconnect_button.sensitive = true
               if login_server
                  login_server.puts "K\n"
                  hashkey = login_server.gets
                  if 'test'[0].class == String
                     password = pass_entry.text.split('').collect { |c| c.getbyte(0) }
                     hashkey = hashkey.split('').collect { |c| c.getbyte(0) }
                  else
                     password = pass_entry.text.split('').collect { |c| c[0] }
                     hashkey = hashkey.split('').collect { |c| c[0] }
                  end
                  # pass_entry.text = String.new
                  password.each_index { |i| password[i] = ((password[i]-32)^hashkey[i])+32 }
                  password = password.collect { |c| c.chr }.join
                  login_server.puts "A\t#{user_id_entry.text}\t#{password}\n"
                  password = nil
                  response = login_server.gets
                  login_key = /KEY\t([^\t]+)\t/.match(response).captures.first
                  if login_key
                     login_server.puts "M\n"
                     response = login_server.gets
                     if response =~ /^M\t/
                        liststore.clear
                        for game in response.sub(/^M\t/, '').scan(/[^\t]+\t[^\t^\n]+/)
                           game_code, game_name = game.split("\t")
                           login_server.puts "N\t#{game_code}\n"
                           if login_server.gets =~ /STORM/
                              login_server.puts "F\t#{game_code}\n"
                              if login_server.gets =~ /NORMAL|PREMIUM|TRIAL|INTERNAL|FREE/
                                 login_server.puts "G\t#{game_code}\n"
                                 login_server.gets
                                 login_server.puts "P\t#{game_code}\n"
                                 login_server.gets
                                 login_server.puts "C\n"
                                 for code_name in login_server.gets.sub(/^C\t[0-9]+\t[0-9]+\t[0-9]+\t[0-9]+[\t\n]/, '').scan(/[^\t]+\t[^\t^\n]+/)
                                    char_code, char_name = code_name.split("\t")
                                    iter = liststore.append
                                    iter[0] = game_code
                                    iter[1] = game_name
                                    iter[2] = char_code
                                    iter[3] = char_name
                                 end
                              end
                           end
                        end
                        disconnect_button.sensitive = true
                     else
                        login_server.close unless login_server.closed?
                        msgbox.call "Unrecognized response from server (#{response})"
                     end
                  else
                     login_server.close unless login_server.closed?
                     disconnect_button.sensitive = false
                     connect_button.sensitive = true
                     user_id_entry.sensitive = true
                     pass_entry.sensitive = true
                     msgbox.call "Something went wrong... probably invalid user id and/or password.\nserver response: #{response}"
                  end
               end
            }
         }
         treeview.signal_connect('cursor-changed') {
            if login_server
               play_button.sensitive = true
            end
         }
         disconnect_button.signal_connect('clicked') {
            disconnect_button.sensitive = false
            play_button.sensitive = false
            liststore.clear
            login_server.close unless login_server.closed?
            connect_button.sensitive = true
            user_id_entry.sensitive = true
            pass_entry.sensitive = true
         }
         play_button.signal_connect('clicked') {
            play_button.sensitive = false
            game_code = treeview.selection.selected[0]
            char_code = treeview.selection.selected[2]
            if login_server and not login_server.closed?
               login_server.puts "F\t#{game_code}\n"
               login_server.gets
               login_server.puts "G\t#{game_code}\n"
               login_server.gets
               login_server.puts "P\t#{game_code}\n"
               login_server.gets
               login_server.puts "C\n"
               login_server.gets
               login_server.puts "L\t#{char_code}\tSTORM\n"
               response = login_server.gets
               if response =~ /^L\t/
                  login_server.close unless login_server.closed?
                  port = /GAMEPORT=([0-9]+)/.match(response).captures.first
                  host = /GAMEHOST=([^\t\n]+)/.match(response).captures.first
                  key = /KEY=([^\t\n]+)/.match(response).captures.first
                  launch_data = response.sub(/^L\tOK\t/, '').split("\t")
                  login_server.close unless login_server.closed?
                  if wizard_option.active?
                     launch_data.collect! { |line| line.sub(/GAMEFILE=.+/, "GAMEFILE=WIZARD.EXE").sub(/GAME=.+/, "GAME=WIZ") }
                  elsif avalon_option.active?
                     launch_data.collect! { |line| line.sub(/GAME=.+/, "GAME=AVALON") }
                  elsif suks_option.active?
                     launch_data.collect! { |line| line.sub(/GAMEFILE=.+/, "GAMEFILE=WIZARD.EXE").sub(/GAME=.+/, "GAME=SUKS") }
                  end
                  if custom_launch_option.active?
                     launch_data.push "CUSTOMLAUNCH=#{custom_launch_entry.child.text}"
                     unless custom_launch_dir.child.text.empty? or custom_launch_dir.child.text == "(enter working directory for command)"
                        launch_data.push "CUSTOMLAUNCHDIR=#{custom_launch_dir.child.text}"
                     end
                  end
                  if make_quick_option.active?
                     if wizard_option.active?
                        frontend = 'wizard'
                     elsif stormfront_option.active?
                        frontend = 'stormfront'
                     elsif avalon_option.active?
                        frontend = 'avalon'
                     else
                        frontend = 'unkown'
                     end
                     if custom_launch_option.active?
                        custom_launch = custom_launch_entry.child.text
                        if custom_launch_dir.child.text.empty? or custom_launch_dir.child.text == "(enter working directory for command)"
                           custom_launch_dir = nil
                        else
                           custom_launch_dir = custom_launch_dir.child.text
                        end
                     else
                        custom_launch = nil
                        custom_launch_dir = nil
                     end
                     entry_data.push h={ :char_name => treeview.selection.selected[3], :game_code => treeview.selection.selected[0], :game_name => treeview.selection.selected[1], :user_id => user_id_entry.text, :password => pass_entry.text, :frontend => frontend, :custom_launch => custom_launch, :custom_launch_dir => custom_launch_dir }
                     save_entry_data = true
                  end
                  user_id_entry.text = String.new
                  pass_entry.text = String.new
                  window.destroy
                  done = true
               else
                  login_server.close unless login_server.closed?
                  disconnect_button.sensitive = false
                  play_button.sensitive = false
                  connect_button.sensitive = true
                  user_id_entry.sensitive = true
                  pass_entry.sensitive = true
               end
            else
               disconnect_button.sensitive = false
               play_button.sensitive = false
               connect_button.sensitive = true
               user_id_entry.sensitive = true
               pass_entry.sensitive = true
            end
         }
         user_id_entry.signal_connect('activate') {
            pass_entry.grab_focus
         }
         pass_entry.signal_connect('activate') {
            connect_button.clicked
         }

         #
         # link tab
         #

         link_to_web_button = Gtk::Button.new('Link to Website')
         unlink_from_web_button = Gtk::Button.new('Unlink from Website')
         web_button_box = Gtk::HBox.new
         web_button_box.pack_start(link_to_web_button, true, true, 5)
         web_button_box.pack_start(unlink_from_web_button, true, true, 5)
         
         web_order_label = Gtk::Label.new
         web_order_label.text = "Unknown"

         web_box = Gtk::VBox.new
         web_box.pack_start(web_order_label, true, true, 5)
         web_box.pack_start(web_button_box, true, true, 5)

         web_frame = Gtk::Frame.new('Website Launch Chain')
         web_frame.add(web_box)

         link_to_sge_button = Gtk::Button.new('Link to SGE')
         unlink_from_sge_button = Gtk::Button.new('Unlink from SGE')
         sge_button_box = Gtk::HBox.new
         sge_button_box.pack_start(link_to_sge_button, true, true, 5)
         sge_button_box.pack_start(unlink_from_sge_button, true, true, 5)
         
         sge_order_label = Gtk::Label.new
         sge_order_label.text = "Unknown"

         sge_box = Gtk::VBox.new
         sge_box.pack_start(sge_order_label, true, true, 5)
         sge_box.pack_start(sge_button_box, true, true, 5)

         sge_frame = Gtk::Frame.new('SGE Launch Chain')
         sge_frame.add(sge_box)


         refresh_button = Gtk::Button.new(' Refresh ')

         refresh_box = Gtk::HBox.new
         refresh_box.pack_end(refresh_button, false, false, 5)

         install_tab = Gtk::VBox.new
         install_tab.border_width = 5
         install_tab.pack_start(web_frame, false, false, 5)
         install_tab.pack_start(sge_frame, false, false, 5)
         install_tab.pack_start(refresh_box, false, false, 5)

         refresh_button.signal_connect('clicked') {
            install_tab_loaded = true
            if defined?(Win32)
               begin
                  key = Win32.RegOpenKeyEx(:hKey => Win32::HKEY_LOCAL_MACHINE, :lpSubKey => 'Software\\Classes\\Simutronics.Autolaunch\\Shell\\Open\\command', :samDesired => (Win32::KEY_ALL_ACCESS|Win32::KEY_WOW64_32KEY))[:phkResult]
                  web_launch_cmd = Win32.RegQueryValueEx(:hKey => key)[:lpData]
                  real_web_launch_cmd = Win32.RegQueryValueEx(:hKey => key, :lpValueName => 'RealCommand')[:lpData]
               rescue
                  web_launch_cmd = String.new
                  real_web_launch_cmd = String.new
               ensure
                  Win32.RegCloseKey(:hKey => key) rescue nil
               end
               begin
                  key = Win32.RegOpenKeyEx(:hKey => Win32::HKEY_LOCAL_MACHINE, :lpSubKey => 'Software\\Simutronics\\Launcher', :samDesired => (Win32::KEY_ALL_ACCESS|Win32::KEY_WOW64_32KEY))[:phkResult]
                  sge_launch_cmd = Win32.RegQueryValueEx(:hKey => key, :lpValueName => 'Directory')[:lpData]
                  real_sge_launch_cmd = Win32.RegQueryValueEx(:hKey => key, :lpValueName => 'RealDirectory')[:lpData]
               rescue
                  sge_launch_cmd = String.new
                  real_launch_cmd = String.new
               ensure
                  Win32.RegCloseKey(:hKey => key) rescue nil
               end
            elsif defined?(Wine)
               web_launch_cmd = Wine.registry_gets('HKEY_LOCAL_MACHINE\\Software\\Classes\\Simutronics.Autolaunch\\Shell\\Open\\command\\').to_s
               real_web_launch_cmd = Wine.registry_gets('HKEY_LOCAL_MACHINE\\Software\\Classes\\Simutronics.Autolaunch\\Shell\\Open\\command\\RealCommand').to_s
               sge_launch_cmd = Wine.registry_gets('HKEY_LOCAL_MACHINE\\Software\\Simutronics\\Launcher\\Directory').to_s
               real_sge_launch_cmd = Wine.registry_gets('HKEY_LOCAL_MACHINE\\Software\\Simutronics\\Launcher\\RealDirectory').to_s
            else
               web_launch_cmd = String.new
               sge_launch_cmd = String.new
            end
            if web_launch_cmd =~ /lich/i
               link_to_web_button.sensitive = false
               unlink_from_web_button.sensitive = true
               if real_web_launch_cmd =~ /launcher.exe/i
                  web_order_label.text = "Website => Lich => Simu Launcher => Frontend"
               else
                  web_order_label.text = "Website => Lich => Unknown"
               end
            elsif web_launch_cmd =~ /launcher.exe/i
               web_order_label.text = "Website => Simu Launcher => Frontend"
               link_to_web_button.sensitive = true
               unlink_from_web_button.sensitive = false
            else
               web_order_label.text = "Website => Unknown"
               link_to_web_button.sensitive = false
               unlink_from_web_button.sensitive = false
            end
            if sge_launch_cmd =~ /lich/i
               link_to_sge_button.sensitive = false
               unlink_from_sge_button.sensitive = true
               if real_sge_launch_cmd and (defined?(Wine) or File.exists?("#{real_sge_launch_cmd}\\launcher.exe"))
                  sge_order_label.text = "SGE => Lich => Simu Launcher => Frontend"
               else
                  sge_order_label.text = "SGE => Lich => Unknown"
               end
            elsif sge_launch_cmd and (defined?(Wine) or File.exists?("#{sge_launch_cmd}\\launcher.exe"))
               sge_order_label.text = "SGE => Simu Launcher => Frontend"
               link_to_sge_button.sensitive = true
               unlink_from_sge_button.sensitive = false
            else
               sge_order_label.text = "SGE => Unknown"
               link_to_sge_button.sensitive = false
               unlink_from_sge_button.sensitive = false
            end
         }
         link_to_web_button.signal_connect('clicked') {
            link_to_web_button.sensitive = false
            Lich.link_to_sal
            if defined?(Win32)
               refresh_button.clicked
            else
               Lich.msgbox(:message => 'WINE will take 5-30 seconds to update the registry.  Wait a while and click the refresh button.')
            end
         }
         unlink_from_web_button.signal_connect('clicked') {
            unlink_from_web_button.sensitive = false
            Lich.unlink_from_sal
            if defined?(Win32)
               refresh_button.clicked
            else
               Lich.msgbox(:message => 'WINE will take 5-30 seconds to update the registry.  Wait a while and click the refresh button.')
            end
         }
         link_to_sge_button.signal_connect('clicked') {
            link_to_sge_button.sensitive = false
            Lich.link_to_sge
            if defined?(Win32)
               refresh_button.clicked
            else
               Lich.msgbox(:message => 'WINE will take 5-30 seconds to update the registry.  Wait a while and click the refresh button.')
            end
         }
         unlink_from_sge_button.signal_connect('clicked') {
            unlink_from_sge_button.sensitive = false
            Lich.unlink_from_sge
            if defined?(Win32)
               refresh_button.clicked
            else
               Lich.msgbox(:message => 'WINE will take 5-30 seconds to update the registry.  Wait a while and click the refresh button.')
            end
         }


         #
         # put it together and show the window
         #

         notebook = Gtk::Notebook.new
         notebook.append_page(quick_game_entry_tab, Gtk::Label.new('Quick Game Entry'))
         notebook.append_page(game_entry_tab, Gtk::Label.new('Game Entry'))
         notebook.append_page(install_tab, Gtk::Label.new('Link'))
         notebook.signal_connect('switch-page') { |who,page,page_num|
            if (page_num == 2) and not install_tab_loaded
               refresh_button.clicked
            end
         }

         window = Gtk::Window.new
         window.title = "Lich v#{LICH_VERSION}"
         window.border_width = 5
         window.add(notebook)
         window.signal_connect('delete_event') { window.destroy; done = true }
         window.default_width = 400

         window.show_all

         custom_launch_entry.visible = false
         custom_launch_dir.visible = false

         notebook.set_page(1) if entry_data.empty?
      }

      wait_until { done }

      if save_entry_data
         File.open("#{DATA_DIR}/entry.dat", 'w') { |file|
            file.write([Marshal.dump(entry_data)].pack('m'))
         }
      end
      entry_data = nil

      unless launch_data
         Gtk.queue { Gtk.main_quit }
         Thread.kill
      end
   end
   $_SERVERBUFFER_ = LimitedArray.new
   $_SERVERBUFFER_.max_size = 400
   $_CLIENTBUFFER_ = LimitedArray.new
   $_CLIENTBUFFER_.max_size = 100

   Socket.do_not_reverse_lookup = true

   #
   # open the client and have it connect to us
   #
   if argv_options[:sal]
      begin
         launch_data = File.open(argv_options[:sal]) { |file| file.readlines }.collect { |line| line.chomp }
      rescue
         $stdout.puts "error: failed to read launch_file: #{$!}"
         Lich.log "info: launch_file: #{argv_options[:sal]}"
         Lich.log "error: failed to read launch_file: #{$!}\n\t#{$!.backtrace.join("\n\t")}"
         exit
      end
   end
   if launch_data
      unless gamecode = launch_data.find { |line| line =~ /GAMECODE=/ }
         $stdout.puts "error: launch_data contains no GAMECODE info"
         Lich.log "error: launch_data contains no GAMECODE info"
         exit(1)
      end
      unless gameport = launch_data.find { |line| line =~ /GAMEPORT=/ }
         $stdout.puts "error: launch_data contains no GAMEPORT info"
         Lich.log "error: launch_data contains no GAMEPORT info"
         exit(1)
      end
      unless gamehost = launch_data.find { |opt| opt =~ /GAMEHOST=/ }
         $stdout.puts "error: launch_data contains no GAMEHOST info"
         Lich.log "error: launch_data contains no GAMEHOST info"
         exit(1)
      end
      unless game = launch_data.find { |opt| opt =~ /GAME=/ }
         $stdout.puts "error: launch_data contains no GAME info"
         Lich.log "error: launch_data contains no GAME info"
         exit(1)
      end
      if custom_launch = launch_data.find { |opt| opt =~ /CUSTOMLAUNCH=/ }
         custom_launch.sub!(/^.*?\=/, '')
         Lich.log "info: using custom launch command: #{custom_launch}"
      end
      if custom_launch_dir = launch_data.find { |opt| opt =~ /CUSTOMLAUNCHDIR=/ }
         custom_launch_dir.sub!(/^.*?\=/, '')
         Lich.log "info: using working directory for custom launch command: #{custom_launch_dir}"
      end
      if ARGV.include?('--without-frontend')
         $frontend = 'unknown'
         unless (game_key = launch_data.find { |opt| opt =~ /KEY=/ }) && (game_key = game_key.split('=').last.chomp)
            $stdout.puts "error: launch_data contains no KEY info"
            Lich.log "error: launch_data contains no KEY info"
            exit(1)
         end
      elsif game =~ /SUKS/i
         $frontend = 'suks'
         unless (game_key = launch_data.find { |opt| opt =~ /KEY=/ }) && (game_key = game_key.split('=').last.chomp)
            $stdout.puts "error: launch_data contains no KEY info"
            Lich.log "error: launch_data contains no KEY info"
            exit(1)
         end
      elsif game =~ /AVALON/i
         launcher_cmd = "open -n -b Avalon \"%1\""
      elsif custom_launch
         unless (game_key = launch_data.find { |opt| opt =~ /KEY=/ }) && (game_key = game_key.split('=').last.chomp)
            $stdout.puts "error: launch_data contains no KEY info"
            Lich.log "error: launch_data contains no KEY info"
            exit(1)
         end
      else
         unless launcher_cmd = Lich.get_simu_launcher
            $stdout.puts 'error: failed to find the Simutronics launcher'
            Lich.log 'error: failed to find the Simutronics launcher'
            exit(1)
         end
      end
      gamecode = gamecode.split('=').last
      gameport = gameport.split('=').last
      gamehost = gamehost.split('=').last
      game     = game.split('=').last

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
         if custom_launch
            sal_filename = nil
            launcher_cmd = custom_launch.sub(/\%port\%/, localport.to_s).sub(/\%key\%/, game_key.to_s)
            scrubbed_launcher_cmd = custom_launch.sub(/\%port\%/, localport.to_s).sub(/\%key\%/, '[scrubbed key]')
            Lich.log "info: launcher_cmd: #{scrubbed_launcher_cmd}"
         else
            if RUBY_PLATFORM =~ /darwin/i
               localhost = "127.0.0.1"
            else
               localhost = "localhost"
            end
            launch_data.collect! { |line| line.sub(/GAMEPORT=.+/, "GAMEPORT=#{localport}").sub(/GAMEHOST=.+/, "GAMEHOST=#{localhost}") }
            sal_filename = "#{TEMP_DIR}/lich#{rand(10000)}.sal"
            while File.exists?(sal_filename)
               sal_filename = "#{TEMP_DIR}/lich#{rand(10000)}.sal"
            end
            File.open(sal_filename, 'w') { |f| f.puts launch_data }
            launcher_cmd = launcher_cmd.sub('%1', sal_filename)
            launcher_cmd = launcher_cmd.tr('/', "\\") if (RUBY_PLATFORM =~ /mingw|win/i) and (RUBY_PLATFORM !~ /darwin/i)
         end
         begin
            if custom_launch_dir
               Dir.chdir(custom_launch_dir)
            end
            if defined?(Win32)
               launcher_cmd =~ /^"(.*?)"\s*(.*)$/
               dir_file = $1
               param = $2
               dir = dir_file.slice(/^.*[\\\/]/)
               file = dir_file.sub(/^.*[\\\/]/, '')
               if Lich.win32_launch_method and Lich.win32_launch_method =~ /^(\d+):(.+)$/
                  method_num = $1.to_i
                  if $2 == 'fail'
                     method_num = (method_num + 1) % 6 
                  end
               else
                  method_num = 5
               end
               if method_num == 5
                  begin
                     key = Win32.RegOpenKeyEx(:hKey => Win32::HKEY_LOCAL_MACHINE, :lpSubKey => 'Software\\Classes\\Simutronics.Autolaunch\\Shell\\Open\\command', :samDesired => (Win32::KEY_ALL_ACCESS|Win32::KEY_WOW64_32KEY))[:phkResult]
                     if Win32.RegQueryValueEx(:hKey => key)[:lpData] =~ /Launcher\.exe/i
                        associated = true
                     else
                        associated = false
                     end
                  rescue
                     associated = false
                  ensure
                     Win32.RegCloseKey(:hKey => key) rescue nil
                  end
                  unless associated
                     Lich.log "warning: skipping launch method #{method_num + 1} because .sal files are not associated with the Simutronics Launcher"
                     method_num = (method_num + 1) % 6 
                  end
               end
               Lich.win32_launch_method = "#{method_num}:fail"
               if method_num == 0
                  Lich.log "info: launcher_cmd: #{launcher_cmd}"
                  spawn launcher_cmd
               elsif method_num == 1
                  Lich.log "info: launcher_cmd: Win32.ShellExecute(:lpOperation => \"open\", :lpFile => #{file.inspect}, :lpDirectory => #{dir.inspect}, :lpParameters => #{param.inspect})"
                  Win32.ShellExecute(:lpOperation => 'open', :lpFile => file, :lpDirectory => dir, :lpParameters => param)
               elsif method_num == 2
                  Lich.log "info: launcher_cmd: Win32.ShellExecuteEx(:lpOperation => \"runas\", :lpFile => #{file.inspect}, :lpDirectory => #{dir.inspect}, :lpParameters => #{param.inspect})"
                  Win32.ShellExecuteEx(:lpOperation => 'runas', :lpFile => file, :lpDirectory => dir, :lpParameters => param)
               elsif method_num == 3
                  Lich.log "info: launcher_cmd: Win32.AdminShellExecute(:op => \"open\", :file => #{file.inspect}, :dir => #{dir.inspect}, :params => #{param.inspect})"
                  Win32.AdminShellExecute(:op => 'open', :file => file, :dir => dir, :params => param)
               elsif method_num == 4
                  Lich.log "info: launcher_cmd: Win32.AdminShellExecute(:op => \"runas\", :file => #{file.inspect}, :dir => #{dir.inspect}, :params => #{param.inspect})"
                  Win32.AdminShellExecute(:op => 'runas', :file => file, :dir => dir, :params => param)
               else # method_num == 5
                  file = File.expand_path(sal_filename).tr('/', "\\")
                  dir = File.expand_path(File.dirname(sal_filename)).tr('/', "\\")
                  Lich.log "info: launcher_cmd: Win32.ShellExecute(:lpOperation => \"open\", :lpFile => #{file.inspect}, :lpDirectory => #{dir.inspect})"
                  Win32.ShellExecute(:lpOperation => 'open', :lpFile => file, :lpDirectory => dir)
               end
            elsif defined?(Wine) and (game != 'AVALON')
               Lich.log "info: launcher_cmd: #{Wine::BIN} #{launcher_cmd}"
               spawn "#{Wine::BIN} #{launcher_cmd}"
            else
               Lich.log "info: launcher_cmd: #{launcher_cmd}"
               spawn launcher_cmd
            end
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
            if defined?(Win32)
               Lich.msgbox(:message => "error: launch method #{method_num + 1} timed out waiting for the client to connect\n\nTry again and another method will be used.", :icon => :error)
            else
               Lich.msgbox(:message => "error: timeout waiting for client to connect", :icon => :error)
            end
            if sal_filename
               File.delete(sal_filename) rescue()
            end
            listener.close rescue()
            $_CLIENT_.close rescue()
            reconnect_if_wanted.call
            Lich.log "info: exiting..."
            Gtk.queue { Gtk.main_quit } if defined?(Gtk)
            exit
         end
         if defined?(Win32)
            Lich.win32_launch_method = "#{method_num}:success"
         end
         Lich.log 'info: connected'
         listener.close rescue nil
         if sal_filename
            File.delete(sal_filename) rescue nil
         end
      end
      gamehost, gameport = Lich.fix_game_host_port(gamehost, gameport)
      Lich.log "info: connecting to game server (#{gamehost}:#{gameport})"
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
      rescue
         Lich.log "error: #{$!}"
         gamehost, gameport = Lich.break_game_host_port(gamehost, gameport)
         Lich.log "info: connecting to game server (#{gamehost}:#{gameport})"
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
         rescue
            Lich.log "error: #{$!}"
            $_CLIENT_.close rescue nil
            reconnect_if_wanted.call
            Lich.log "info: exiting..."
            Gtk.queue { Gtk.main_quit } if defined?(Gtk)
            exit
         end
      end
      Lich.log 'info: connected'
   elsif game_host and game_port
      unless Lich.hosts_file
         Lich.log "error: cannot find hosts file"
         $stdout.puts "error: cannot find hosts file"
         exit
      end
      game_quad_ip = IPSocket.getaddress(game_host)
      error_count = 0
      begin
         listener = TCPServer.new('127.0.0.1', game_port)
         begin
            listener.setsockopt(Socket::SOL_SOCKET,Socket::SO_REUSEADDR,1)
         rescue
            Lich.log "warning: setsockopt with SO_REUSEADDR failed: #{$!}"
         end
      rescue
         sleep 1
         if (error_count += 1) >= 30
            $stdout.puts 'error: failed to bind to the proper port'
            Lich.log 'error: failed to bind to the proper port'
            exit!
         else
            retry
         end
      end
      Lich.modify_hosts(game_host)

      $stdout.puts "Pretending to be #{game_host}"
      $stdout.puts "Listening on port #{game_port}"
      $stdout.puts "Waiting for the client to connect..."
      Lich.log "info: pretending to be #{game_host}"
      Lich.log "info: listening on port #{game_port}"
      Lich.log "info: waiting for the client to connect..."

      timeout_thread = Thread.new {
         sleep 120
         listener.close rescue nil
         $stdout.puts 'error: timed out waiting for client to connect'
         Lich.log 'error: timed out waiting for client to connect'
         Lich.restore_hosts
         exit
      }
#      $_CLIENT_ = listener.accept
      $_CLIENT_ = SynchronizedSocket.new(listener.accept)
      listener.close rescue nil
      timeout_thread.kill
      $stdout.puts "Connection with the local game client is open."
      Lich.log "info: connection with the game client is open"
      Lich.restore_hosts
      if test_mode
         $_SERVER_ = $stdin # fixme
         $_CLIENT_.puts "Running in test mode: host socket set to stdin."
      else
         Lich.log 'info: connecting to the real game host...'
         game_host, game_port = Lich.fix_game_host_port(game_host, game_port)
         begin
            timeout_thread = Thread.new {
               sleep 30
               Lich.log "error: timed out connecting to #{game_host}:#{game_port}"
               $stdout.puts "error: timed out connecting to #{game_host}:#{game_port}"
               exit
            }
            begin
               Game.open(game_host, game_port)
            rescue
               Lich.log "error: #{$!}"
               $stdout.puts "error: #{$!}"
               exit
            end
            timeout_thread.kill rescue nil
            Lich.log 'info: connection with the game host is open'
         end
      end
   else
      # offline mode removed
      Lich.log "error: don't know what to do"
      exit
   end

   listener = timeout_thr = nil

   #
   # drop superuser privileges
   #
   unless (RUBY_PLATFORM =~ /mingw|win/i) and (RUBY_PLATFORM !~ /darwin/i)
      Lich.log "info: dropping superuser privileges..."
      begin
         Process.uid = `id -ru`.strip.to_i
         Process.gid = `id -rg`.strip.to_i
         Process.egid = `id -rg`.strip.to_i
         Process.euid = `id -ru`.strip.to_i
      rescue SecurityError
         Lich.log "error: failed to drop superuser privileges: #{$!}\n\t#{$!.backtrace.join("\n\t")}"
      rescue SystemCallError
         Lich.log "error: failed to drop superuser privileges: #{$!}\n\t#{$!.backtrace.join("\n\t")}"
      rescue
         Lich.log "error: failed to drop superuser privileges: #{$!}\n\t#{$!.backtrace.join("\n\t")}"
      end
   end

   # backward compatibility
   if $frontend =~ /^(?:wizard|avalon)$/
      $fake_stormfront = true
   else
      $fake_stormfront = false
   end

   undef :exit!

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
         # Somehow... for some ridiculous reason... Windows doesn't let us close the socket if we shut it down first...
         # listener.shutdown
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
            for client_string in [ "#{$cmd_prefix}_injury 2", "#{$cmd_prefix}_flag Display Inventory Boxes 1", "#{$cmd_prefix}_flag Display Dialog Boxes 0" ]
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

   if detachable_client_port
      detachable_client_thread = Thread.new {
         loop {
            begin
               server = TCPServer.new('127.0.0.1', detachable_client_port)
               $_DETACHABLE_CLIENT_ = SynchronizedSocket.new(server.accept)
               $_DETACHABLE_CLIENT_.sync = true
            rescue
               Lich.log "#{$!}\n\t#{$!.backtrace.join("\n\t")}"
               server.close rescue nil
               $_DETACHABLE_CLIENT_.close rescue nil
               $_DETACHABLE_CLIENT_ = nil
               sleep 5
               next
            ensure
               server.close rescue nil
            end
            if $_DETACHABLE_CLIENT_
               begin
                  $frontend = 'profanity'
                  Thread.new {
                     100.times { sleep 0.1; break if XMLData.indicator['IconJOINED'] }
                     init_str = "<progressBar id='mana' value='0' text='mana #{XMLData.mana}/#{XMLData.max_mana}'/>"
                     init_str.concat "<progressBar id='health' value='0' text='health #{XMLData.health}/#{XMLData.max_health}'/>"
                     init_str.concat "<progressBar id='spirit' value='0' text='spirit #{XMLData.spirit}/#{XMLData.max_spirit}'/>"
                     init_str.concat "<progressBar id='stamina' value='0' text='stamina #{XMLData.stamina}/#{XMLData.max_stamina}'/>"
                     init_str.concat "<progressBar id='encumlevel' value='#{XMLData.encumbrance_value}' text='#{XMLData.encumbrance_text}'/>"
                     init_str.concat "<progressBar id='pbarStance' value='#{XMLData.stance_value}'/>"
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
                  while client_string = $_DETACHABLE_CLIENT_.gets
                     client_string = "#{$cmd_prefix}#{client_string}" # if $frontend =~ /^(?:wizard|avalon)$/
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
                  $_DETACHABLE_CLIENT_.close rescue nil
                  $_DETACHABLE_CLIENT_ = nil
               ensure 
                  $_DETACHABLE_CLIENT_.close rescue nil
                  $_DETACHABLE_CLIENT_ = nil
               end
            end
            sleep 0.1
         }
      }
   else
      detachable_client_thread = nil
   end

   wait_while { $offline_mode }

   if $frontend == 'wizard'
      $link_highlight_start = "\207"
      $link_highlight_end = "\240"
      $speech_highlight_start = "\212"
      $speech_highlight_end = "\240"
   end

   client_thread.priority = 3

   $_CLIENT_.puts "\n--- Lich v#{LICH_VERSION} is active.  Type #{$clean_lich_char}help for usage info.\n\n"

   Game.thread.join
   client_thread.kill rescue nil
   detachable_client_thread.kill rescue nil

   Lich.log 'info: stopping scripts...'
   Script.running.each { |script| script.kill }
   Script.hidden.each { |script| script.kill }
   200.times { sleep 0.1; break if Script.running.empty? and Script.hidden.empty? }
   Lich.log 'info: saving script settings...'
   Settings.save
   Vars.save
   Lich.log 'info: closing connections...'
   Game.close
   $_CLIENT_.close rescue nil
#   Lich.db.close rescue nil
   reconnect_if_wanted.call
   Lich.log "info: exiting..."
   Gtk.queue { Gtk.main_quit } if defined?(Gtk)
   exit
}

if defined?(Gtk)
   Thread.current.priority = -10
   Gtk.main
else
   main_thread.join
end
exit
