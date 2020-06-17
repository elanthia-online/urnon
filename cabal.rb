#!/usr/bin/env ruby

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
require 'benchmark'
require 'time'
require 'socket'
require 'rexml/document'
require 'rexml/streamlistener'
require 'stringio'
require 'zlib'
require 'resolv'
require 'digest/md5'
require 'sqlite3'
require 'openssl'
require 'fileutils'
# lich globals
LICH_VERSION = '4.6.50'
TESTING = false
$VERBOSE = nil
$link_highlight_start = ''
$link_highlight_end = ''
$speech_highlight_start = ''
$speech_highlight_end = ''
$SEND_CHARACTER = '>'
$cmd_prefix = '<c>'
$clean_lich_char = ';' # fixme
$lich_char = Regexp.escape($clean_lich_char)
# deprecated stuff
$version = LICH_VERSION
$room_count = 0


require_relative("./lib/lich")
## primative extensions to String, etc
require_relative("./lib/ext")
require_relative("./lib/string-proc")
require_relative("./lib/synchronized-socket")
require_relative("./lib/limited-array")
require_relative("./lib/xml-parser")
require_relative("./lib/upstream-hook")
require_relative("./lib/downstream-hook")
require_relative("./lib/setting")
require_relative("./lib/game-settings")
require_relative("./lib/vars")
require_relative("./lib/watchfor")
require_relative("./lib/script")
require_relative("./lib/exec-script")
require_relative("./lib/map")
require_relative("./lib/room")
require_relative("./lib/autostart")
require_relative("./lib/settings")
require_relative("./lib/char-settings")
require_relative("./lib/format")
require_relative("./lib/globals")
require_relative("./lib/buffer")
require_relative("./lib/shared-buffer")
require_relative("./lib/spell-ranks")
require_relative("./lib/games")
require_relative("./lib/eaccess")
require_relative("./lib/decoders")
require_relative("./lib/settings")
# method aliases for legacy APIs
require_relative("./lib/aliases.rb")
require_relative("./lib/opts.rb")
require_relative("./lib/game-portal")
require_relative("./lib/spell-song")
# legacy top-level include
include Games::Gemstone

XMLData      = XMLParser.new
LICH_DIR   ||= File.dirname(File.expand_path($PROGRAM_NAME))
TEMP_DIR   ||= "#{LICH_DIR}/temp"
DATA_DIR   ||= "#{LICH_DIR}/data"
SCRIPT_DIR ||= "#{LICH_DIR}/scripts"
MAP_DIR    ||= "#{LICH_DIR}/maps"
LOG_DIR    ||= "#{LICH_DIR}/logs"
BACKUP_DIR ||= "#{LICH_DIR}/backup"

[TEMP_DIR, DATA_DIR, SCRIPT_DIR, MAP_DIR, LOG_DIR, BACKUP_DIR].each do |dir| FileUtils.mkdir_p(dir) end
Lich.init_db

argv = Opts.parse(ARGV)
argv.port      or fail Exception, "--port= is required"
argv.password  or fail Exception, "--password= is required"
argv.account   or fail Exception, "--account= is required"
argv.character or fail Exception, "--character= is required"

game_key = EAccess.auth(
  account: argv.account, 
  password: argv.password,
  character: argv.character)

$_SERVERBUFFER_ = LimitedArray.new
$_SERVERBUFFER_.max_size = 400
$_CLIENTBUFFER_ = LimitedArray.new
$_CLIENTBUFFER_.max_size = 100
#
# connect to GSIV only for right now
#
Game.open(
  argv["game-host"] || 'storm.gs4.game.play.net', 
  argv["game-port"] || 10024)
#
# send the login key
#
Game._puts(game_key + "\n")
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


detachable_client_thread = Thread.new {
    loop {
      begin
          server = TCPServer.new('127.0.0.1', argv.port)
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
                client_string = "#{$cmd_prefix}#{client_string}" 
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
          ensure 
            $_DETACHABLE_CLIENT_.close rescue nil
            $_DETACHABLE_CLIENT_ = nil
          end
      end
      sleep 0.1
    }
}

wait_until {Game.closed?}
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
Lich.log "info: exiting..."