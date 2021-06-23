require 'fileutils'

module Urnon
  class XMLParser
    attr_reader :mana, :max_mana, :health, :max_health, :spirit, :max_spirit,
                :last_spirit, :stamina, :max_stamina, :stance_text, :stance_value,
                :mind_text, :mind_value, :prepared_spell, :encumbrance_text,
                :encumbrance_full_text, :encumbrance_value, :indicator,
                :injuries, :injury_mode,
                :room_count, :room_title, :room_description, :room_exits, :room_id,
                :room_exits_string, :familiar_room_title, :familiar_room_description,
                :familiar_room_exits, :bounty_task, :injury_mode, :server_time,
                :server_time_offset, :roundtime_end, :cast_roundtime_end, :last_pulse,
                :level, :next_level_value, :next_level_text, :society_task,
                :stow_container_id, :name, :game, :in_stream, :player_id,
                :active_spells, :prompt, :current_target_ids, :current_target_id,
                :room_window_disabled, :session

    attr_accessor :send_fake_tags

    include REXML::StreamListener

    def initialize(session)
      @session   = session
      @buffer = ''
      @unescape = { 'lt' => '<', 'gt' => '>', 'quot' => '"', 'apos' => "'", 'amp' => '&' }
      @bold = false
      @active_tags = []
      @active_ids = []
      @last_tag = ''
      @last_id = ''
      @current_stream = ''
      @current_style = ''
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
      @fam_mode = ''
      @room_window_disabled = false
      @wound_gsl = ''
      @scar_gsl = ''
      @send_fake_tags = false
      @prompt = ''
      @nerve_tracker_num = 0
      @nerve_tracker_active = 'no'
      @server_time = Time.now.to_i
      @server_time_offset = 0
      @roundtime_end = 0
      @cast_roundtime_end = 0
      @last_pulse = Time.now.to_i
      @level = 0
      @next_level_value = 0
      @next_level_text = ''
      @current_target_ids = []

      @room_count = 0
      @room_updating = false
      @room_title = ''
      @room_id    = nil
      @room_description = ''
      @room_exits = []
      @room_exits_string = ''

      @familiar_room_title = ''
      @familiar_room_description = ''
      @familiar_room_exits = []

      @bounty_task = ''
      @society_task = ''

      @name = ''
      @game = ''
      @player_id = ''
      @mana = 0
      @max_mana = 0
      @health = 0
      @max_health = 0
      @spirit = 0
      @max_spirit = 0
      @last_spirit = nil
      @stamina = 0
      @max_stamina = 0
      @stance_text = ''
      @stance_value = 0
      @mind_text = ''
      @mind_value = 0
      @prepared_spell = 'None'
      @encumbrance_text = ''
      @encumbrance_full_text = ''
      @encumbrance_value = 0
      @indicator = Hash.new
      @injuries = {'back' => {'scar' => 0, 'wound' => 0}, 'leftHand' => {'scar' => 0, 'wound' => 0}, 'rightHand' => {'scar' => 0, 'wound' => 0}, 'head' => {'scar' => 0, 'wound' => 0}, 'rightArm' => {'scar' => 0, 'wound' => 0}, 'abdomen' => {'scar' => 0, 'wound' => 0}, 'leftEye' => {'scar' => 0, 'wound' => 0}, 'leftArm' => {'scar' => 0, 'wound' => 0}, 'chest' => {'scar' => 0, 'wound' => 0}, 'leftFoot' => {'scar' => 0, 'wound' => 0}, 'rightFoot' => {'scar' => 0, 'wound' => 0}, 'rightLeg' => {'scar' => 0, 'wound' => 0}, 'neck' => {'scar' => 0, 'wound' => 0}, 'leftLeg' => {'scar' => 0, 'wound' => 0}, 'nsys' => {'scar' => 0, 'wound' => 0}, 'rightEye' => {'scar' => 0, 'wound' => 0}}
      @injury_mode = 0

      @active_spells = Hash.new
    end

    def updating_room?
      @room_updating
    end

    def reset
      @active_tags = []
      @active_ids = []
      @current_stream = ''
      @current_style = ''
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
          elsif name == 'resource'
            nil
          elsif name == 'nav'
            @room_id = attributes['rm'].to_i
          elsif name == 'pushStream'
            @in_stream = true
            @current_stream = attributes['id'].to_s
            @session.game_obj_registry.clear_inv if attributes['id'].to_s == 'inv'
          elsif name == 'popStream'
            if attributes['id'] == 'room'
                unless @room_window_disabled
                  @room_count += 1
                  @room_updating = false
                end
            end
            @in_stream = false
            if attributes['id'] == 'bounty'
                @bounty_task.strip!
            end
            @current_stream = ''
          elsif name == 'pushBold'
            @bold = true
          elsif name == 'popBold'
            @bold = false
          elsif (name == 'streamWindow')
            if (attributes['id'] == 'main') and attributes['subtitle']
                @room_updating = true
                @room_title = '[' + attributes['subtitle'][3..-1] + ']'
            end
          elsif name == 'style'
            @current_style = attributes['id']
          elsif name == 'prompt'
            @server_time = attributes['time'].to_i
            @server_time_offset = (Time.now.to_i - @server_time)
            @session.puts "\034GSq#{sprintf('%010d', @server_time)}\r\n" if @send_fake_tags
          elsif (name == 'compDef') or (name == 'component')
            if attributes['id'] == 'room objs'
                @session.game_obj_registry.clear_loot
                @session.game_obj_registry.clear_npcs
            elsif attributes['id'] == 'room players'
                @session.game_obj_registry.clear_pcs
            elsif attributes['id'] == 'room exits'
                @room_exits = []
                @room_exits_string = ''
            elsif attributes['id'] == 'room desc'
                @room_description = ''
                @session.game_obj_registry.clear_room_desc
            elsif attributes['id'] == 'room extra' # DragonRealms
                @room_count += 1
                @room_updating = false
            # elsif attributes['id'] == 'sprite'
            end
          elsif name == 'clearContainer'
            if attributes['id'] == 'stow'
                @session.game_obj_registry.clear_container(@stow_container_id)
            else
                @session.game_obj_registry.clear_container(attributes['id'])
            end
          elsif name == 'deleteContainer'
            @session.game_obj_registry.delete_container(attributes['id'])
          elsif name == 'progressBar'
            if attributes['id'] == 'pbarStance'
                @stance_text = attributes['text'].split.first
                @stance_value = attributes['value'].to_i
                @session.puts "\034GSg#{sprintf('%010d', @stance_value)}\r\n" if @send_fake_tags
            elsif attributes['id'] == 'mana'
                last_mana = @mana
                @mana, @max_mana = attributes['text'].scan(/-?\d+/).collect { |num| num.to_i }
                _difference = @mana - last_mana
                if @send_fake_tags
                  @session.puts "\034GSV#{sprintf('%010d%010d%010d%010d%010d%010d%010d%010d', @max_health.to_i, @health.to_i, @max_spirit.to_i, @spirit.to_i, @max_mana.to_i, @mana.to_i, @wound_gsl, @scar_gsl)}\r\n"
                end
            elsif attributes['id'] == 'stamina'
                @stamina, @max_stamina = attributes['text'].scan(/-?\d+/).collect { |num| num.to_i }
            elsif attributes['id'] == 'mindState'
                @mind_text = attributes['text']
                @mind_value = attributes['value'].to_i
                @session.puts "\034GSr#{MINDMAP[@mind_text]}\r\n" if @send_fake_tags
            elsif attributes['id'] == 'health'
                @health, @max_health = attributes['text'].scan(/-?\d+/).collect { |num| num.to_i }
                @session.puts "\034GSV#{sprintf('%010d%010d%010d%010d%010d%010d%010d%010d', @max_health.to_i, @health.to_i, @max_spirit.to_i, @spirit.to_i, @max_mana.to_i, @mana.to_i, @wound_gsl, @scar_gsl)}\r\n" if @send_fake_tags
            elsif attributes['id'] == 'spirit'
                @last_spirit = @spirit if @last_spirit
                @spirit, @max_spirit = attributes['text'].scan(/-?\d+/).collect { |num| num.to_i }
                @last_spirit = @spirit unless @last_spirit
                @session.puts "\034GSV#{sprintf('%010d%010d%010d%010d%010d%010d%010d%010d', @max_health.to_i, @health.to_i, @max_spirit.to_i, @spirit.to_i, @max_mana.to_i, @mana.to_i, @wound_gsl, @scar_gsl)}\r\n" if @send_fake_tags
            elsif attributes['id'] == 'nextLvlPB'
                @session.gift.pulse unless @next_level_text == attributes['text']
                @next_level_value = attributes['value'].to_i
                @next_level_text = attributes['text']
            elsif attributes['id'] == 'encumlevel'
                @encumbrance_value = attributes['value'].to_i
                @encumbrance_text = attributes['text']
            end
          elsif name == 'roundTime'
            @roundtime_end = attributes['value'].to_i
            @session.puts "\034GSQ#{sprintf('%010d', @roundtime_end)}\r\n" if @send_fake_tags
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
                      @session.puts "\034GSJ0000000000000000000100000000001\r\n"
                  else
                      @session.puts "\034GSJ0000000000000000000000000000000\r\n"
                  end
                elsif attributes['id'] == 'IconDISEASED'
                  if attributes['visible'] == 'y'
                      @session.puts "\034GSK0000000000000000000100000000001\r\n"
                  else
                      @session.puts "\034GSK0000000000000000000000000000000\r\n"
                  end
                else
                  gsl_prompt = ''; ICONMAP.keys.each { |icon| gsl_prompt += ICONMAP[icon] if @indicator[icon] == 'y' }
                  @session.puts "\034GSP#{sprintf('%-30s', gsl_prompt)}\r\n"
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
                                  @session.puts "\034GSV#{sprintf('%010d%010d%010d%010d%010d%010d%010d%010d', @max_health.to_i, @health.to_i, @max_spirit.to_i, @spirit.to_i, @max_mana.to_i, @mana.to_i, make_wound_gsl, make_scar_gsl)}\r\n" if @send_fake_tags
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
                        @session._puts "#{$cmd_prefix}health"
                      }
                  end
                else
                  @injuries[attributes['id']]['wound'] = 0
                  @injuries[attributes['id']]['scar'] = 0
                end
            end
            @session.puts "\034GSV#{sprintf('%010d%010d%010d%010d%010d%010d%010d%010d', @max_health.to_i, @health.to_i, @max_spirit.to_i, @spirit.to_i, @max_mana.to_i, @mana.to_i, make_wound_gsl, make_scar_gsl)}\r\n" if @send_fake_tags
          elsif name == 'compass'
            if @current_stream == 'familiar'
                @fam_mode = ''
            elsif @room_window_disabled
                @room_exits = []
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
                @level = @session.stats.level = attributes['value'].slice(/\d+/).to_i
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
                @bounty_task = ''
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
            @game = 'unknown' if @game.nil? or @game.empty?
            @session.register()
            FileUtils.mkdir_p File.join(DATA_DIR, @game, @name)
            if $frontend =~ /^(?:wizard|avalon)$/
              @session._puts "#{$cmd_prefix}_flag Display Dialog Boxes 0"
              sleep 0.05
              @session._puts "#{$cmd_prefix}_injury 2"
              sleep 0.05
              # fixme: game name hardcoded as Gemstone IV; maybe doesn't make any difference to the client
              @session.puts "\034GSB0000000000#{attributes['char']}\r\n\034GSA#{Time.now.to_i.to_s}GemStone IV\034GSD\r\n"
              # Sending fake GSL tags to the Wizard FE is disabled until now, because it doesn't accept the tags and just gives errors until initialized with the above line
              @send_fake_tags = true
              # Send all the tags we missed out on
              @session.puts "\034GSV#{sprintf('%010d%010d%010d%010d%010d%010d%010d%010d', @max_health.to_i, @health.to_i, @max_spirit.to_i, @spirit.to_i, @max_mana.to_i, @mana.to_i, make_wound_gsl, make_scar_gsl)}\r\n"
              @session.puts "\034GSg#{sprintf('%010d', @stance_value)}\r\n"
              @session.puts "\034GSr#{MINDMAP[@mind_text]}\r\n"
              gsl_prompt = ''
              @indicator.keys.each { |icon| gsl_prompt += ICONMAP[icon] if @indicator[icon] == 'y' }
              @session.puts "\034GSP#{sprintf('%-30s', gsl_prompt)}\r\n"
              gsl_prompt = nil
              gsl_exits = ''
              @room_exits.each { |exit| gsl_exits.concat(DIRMAP[SHORTDIR[exit]].to_s) }
              @session.puts "\034GSj#{sprintf('%-20s', gsl_exits)}\r\n"
              gsl_exits = nil
              @session.puts "\034GSn#{sprintf('%-14s', @prepared_spell)}\r\n"
              @session.puts "\034GSm#{sprintf('%-45s', @session.game_obj_registry.right_hand.name)}\r\n"
              @session.puts "\034GSl#{sprintf('%-45s', @session.game_obj_registry.left_hand.name)}\r\n"
              @session.puts "\034GSq#{sprintf('%010d', @server_time)}\r\n"
              @session.puts "\034GSQ#{sprintf('%010d', @roundtime_end)}\r\n" if @roundtime_end > 0
            end
            @session._puts("#{$cmd_prefix}_flag Display Inventory Boxes 1")

            Thread.new {
              begin
                sleep 0.1 until self.session.client_sock
                Autostart.call(self.session)
              rescue Exception => e
                $stderr << e.message
                $stderr << e.backtrace.join("\n")
                self.session.to_client(e.message, e.backtrace.join("\n"))
              end
            }
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
          # @session.write(text_string) unless ($frontend != 'suks') or (@current_stream =~ /^(?:spellfront|inv|bounty|society)$/) or @active_tags.any? { |tag| tag =~ /^(?:compDef|inv|component|right|left|spell)$/ } or (@active_tags.include?('stream') and @active_ids.include?('Spells')) or (text_string == "\n" and (@last_tag =~ /^(?:popStream|prompt|compDef|dialogData|openDialog|switchQuickBar|component)$/))
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
            @session.game_obj_registry.new_right_hand(@session, @obj_exist, @obj_noun, text_string)
            @session.puts "\034GSm#{sprintf('%-45s', text_string)}\r\n" if @send_fake_tags
          elsif @active_tags.include?('left')
            @session.game_obj_registry.new_left_hand(@session, @obj_exist, @obj_noun, text_string)
            @session.puts "\034GSl#{sprintf('%-45s', text_string)}\r\n" if @send_fake_tags
          elsif @active_tags.include?('spell')
            @prepared_spell = text_string
            @session.puts "\034GSn#{sprintf('%-14s', text_string)}\r\n" if @send_fake_tags
          elsif @active_tags.include?('compDef') or @active_tags.include?('component')
            if @active_ids.include?('room objs')
                if @active_tags.include?('a')
                  if @bold
                      @session.game_obj_registry.new_npc(@session, @obj_exist, @obj_noun, text_string)
                  else
                      @session.game_obj_registry.new_loot(@session, @obj_exist, @obj_noun, text_string)
                  end
                elsif (text_string =~ /that (?:is|appears) ([\w\s]+)(?:,| and|\.)/) or (text_string =~ / \(([^\(]+)\)/)
                  @session.game_obj_registry.npcs[-1].status = $1
                end
            elsif @active_ids.include?('room players')
                if @active_tags.include?('a')
                  @pc = @session.game_obj_registry.new_pc(@session, @obj_exist, @obj_noun, "#{@player_title}#{text_string}", @player_status)
                  @player_status = nil
                else
                  if @game =~ /^DR/
                      @session.game_obj_registry.clear_pcs
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
                        @session.game_obj_registry.new_pc(@session, nil, noun, player, status)
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
                      @session.game_obj_registry.new_room_desc(@session, @obj_exist, @obj_noun, text_string)
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
            @session.game_obj_registry.new_inv(@session, @obj_exist, @obj_noun, text_string, nil)
          elsif @current_stream == 'familiar'
            # fixme: familiar room tracking does not (can not?) auto update, status of pcs and npcs isn't tracked at all, titles of pcs aren't tracked
            if @current_style == 'roomName'
                @familiar_room_title = text_string
                @familiar_room_description = ''
                @familiar_room_exits = []
                @session.game_obj_registry.clear_fam_room_desc
                @session.game_obj_registry.clear_fam_loot
                @session.game_obj_registry.clear_fam_npcs
                @session.game_obj_registry.clear_fam_pcs
                @fam_mode = ''
            elsif @current_style == 'roomDesc'
                @familiar_room_description.concat(text_string)
                if @active_tags.include?('a')
                  @session.game_obj_registry.new_fam_room_desc(@session, @obj_exist, @obj_noun, text_string)
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
                      @session.game_obj_registry.new_fam_npc(@session, @obj_exist, @obj_noun, text_string)
                  else
                      @session.game_obj_registry.new_fam_loot(@session, @obj_exist, @obj_noun, text_string)
                  end
                end
                # puts 'things: ' + text_string
            elsif @fam_mode == 'people' and @active_tags.include?('a')
                @session.game_obj_registry.new_fam_pc(@session, @obj_exist, @obj_noun, text_string)
                # puts 'people: ' + text_string
            elsif (@fam_mode == 'paths') and @active_tags.include?('a')
                @familiar_room_exits.push(text_string)
            end
          elsif @room_window_disabled
            if @current_style == 'roomDesc'
                @room_description.concat(text_string)
                if @active_tags.include?('a')
                  @session.game_obj_registry.new_room_desc(@session, @obj_exist, @obj_noun, text_string)
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
                  @session.game_obj_registry.delete_container(@stow_container_id)
                end
            elsif @obj_exist
                @session.game_obj_registry.new_inv(@session, @obj_exist, @obj_noun, @obj_name, @obj_location, @obj_before_name, @obj_after_name)
            end
          elsif @send_fake_tags and (@active_ids.last == 'room exits')
            gsl_exits = ''
            @room_exits.each { |exit| gsl_exits.concat(DIRMAP[SHORTDIR[exit]].to_s) }
            @session.puts "\034GSj#{sprintf('%-20s', gsl_exits)}\r\n"
            gsl_exits = nil
          elsif @room_window_disabled and (name == 'compass')

            @room_description = @room_description.strip
            @room_exits_string.concat " #{@room_exits.join(', ')}" unless @room_exits.empty?
            gsl_exits = ''
            @room_exits.each { |exit| gsl_exits.concat(DIRMAP[SHORTDIR[exit]].to_s) }
            @session.puts "\034GSj#{sprintf('%-20s', gsl_exits)}\r\n"
            gsl_exits = nil
            @room_count += 1
            @room_updating = false
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
  end
end
