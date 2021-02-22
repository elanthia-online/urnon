class Spells
  class Record
    attr_reader :num, :name, :timestamp, :msgup, :msgdn,
                :circle, :type, :cast_proc,
                :real_time, :persist_on_death, :availability, :no_incant
    attr_accessor :stance, :channel

    def initialize(xml_spell)
      @num = xml_spell.attributes['number'].to_i
      @name = xml_spell.attributes['name']
      @type = xml_spell.attributes['type']
      @no_incant = ((xml_spell.attributes['incant'] == 'no') ? true : false)
      if xml_spell.attributes['availability'] == 'all'
        @availability = 'all'
      elsif xml_spell.attributes['availability'] == 'group'
        @availability = 'group'
      else
        @availability = 'self-cast'
      end
      @bonus = Hash.new
      xml_spell.elements.find_all { |e| e.name == 'bonus' }.each { |e|
        @bonus[e.attributes['type']] = e.text
        @bonus[e.attributes['type']].untaint
      }
      @msgup = xml_spell.elements.find_all { |e| (e.name == 'message') and (e.attributes['type'].downcase == 'start') }.collect { |e| e.text }.join('$|^')
      @msgup = nil if @msgup.empty?
      @msgdn = xml_spell.elements.find_all { |e| (e.name == 'message') and (e.attributes['type'].downcase == 'end') }.collect { |e| e.text }.join('$|^')
      @msgdn = nil if @msgdn.empty?
      @stance = ((xml_spell.attributes['stance'] =~ /^(yes|true)$/i) ? true : false)
      @channel = ((@xml_spell.attributes['channel'] =~ /^(yes|true)$/i) ? true : false)
      @cost = Hash.new
      xml_spell.elements.find_all { |e| e.name == 'cost' }.each { |xml_cost|
        @cost[xml_cost.attributes['type'].downcase] ||= Hash.new
        if xml_cost.attributes['cast-type'].downcase == 'target'
          @cost[xml_cost.attributes['type'].downcase]['target'] = xml_cost.text
        else
          @cost[xml_cost.attributes['type'].downcase]['self'] = xml_cost.text
        end
      }
      @duration = Hash.new
      xml_spell.elements.find_all { |e| e.name == 'duration' }.each { |xml_duration|
        if xml_duration.attributes['cast-type'].downcase == 'target'
          cast_type = 'target'
        else
          cast_type = 'self'
          if xml_duration.attributes['real-time'] =~ /^(yes|true)$/i
            @real_time = true
          else
            @real_time = false
          end
        end
        @duration[cast_type] = Hash.new
        @duration[cast_type][:duration] = xml_duration.text
        @duration[cast_type][:stackable] = (xml_duration.attributes['span'].downcase == 'stackable')
        @duration[cast_type][:refreshable] = (xml_duration.attributes['span'].downcase == 'refreshable')
        if xml_duration.attributes['multicastable'] =~ /^(yes|true)$/i
          @duration[cast_type][:multicastable] = true
        else
          @duration[cast_type][:multicastable] = false
        end
        if xml_duration.attributes['persist-on-death'] =~ /^(yes|true)$/i
          @persist_on_death = true
        else
          @persist_on_death = false
        end
        if xml_duration.attributes['max']
          @duration[cast_type][:max_duration] = xml_duration.attributes['max'].to_f
        else
          @duration[cast_type][:max_duration] = 250.0
        end
      }
      @cast_proc = xml_spell.elements['cast-proc'].text
      @cast_proc.untaint
      @timestamp = Time.now
      @timeleft = 0
      @circle = (num.to_s.length == 3 ? num.to_s[0..0] : num.to_s[0..1])
      self
    end

    def time_per_formula(options={})
      activator_modifier = { 'tap' => 0.5, 'rub' => 1, 'wave' => 1, 'raise' => 1.33, 'drink' => 0, 'bite' => 0, 'eat' => 0, 'gobble' => 0 }
      can_haz_spell_ranks = /Spells\.(?:minorelemental|majorelemental|minorspiritual|majorspiritual|wizard|sorcerer|ranger|paladin|empath|cleric|bard|minormental)/
      skills = [ 'Spells.minorelemental', 'Spells.majorelemental', 'Spells.minorspiritual', 'Spells.majorspiritual', 'Spells.wizard', 'Spells.sorcerer', 'Spells.ranger', 'Spells.paladin', 'Spells.empath', 'Spells.cleric', 'Spells.bard', 'Spells.minormental', 'Skills.magicitemuse', 'Skills.arancesymbols' ]
      if options[:caster] and (options[:caster] !~ /^(?:self|#{XMLData.name})$/i)
        if options[:target] and (options[:target].downcase == options[:caster].downcase)
          formula = @duration['self'][:duration].to_s.dup
        else
          formula = @duration['target'][:duration].dup || @duration['self'][:duration].to_s.dup
        end
        if options[:activator] =~ /^(#{activator_modifier.keys.join('|')})$/i
          if formula =~ can_haz_spell_ranks
            skills.each { |skill_name| formula.gsub!(skill_name, "(SpellRanks['#{options[:caster]}'].magicitemuse * #{activator_modifier[options[:activator]]}).to_i") }
            formula = "(#{formula})/2.0"
          elsif formula =~ /Skills\.(?:magicitemuse|arancesymbols)/
            skills.each { |skill_name| formula.gsub!(skill_name, "(SpellRanks['#{options[:caster]}'].magicitemuse * #{activator_modifier[options[:activator]]}).to_i") }
          end
        elsif options[:activator] =~ /^(invoke|scroll)$/i
          if formula =~ can_haz_spell_ranks
            skills.each { |skill_name| formula.gsub!(skill_name, "SpellRanks['#{options[:caster]}'].arcanesymbols.to_i") }
            formula = "(#{formula})/2.0"
          elsif formula =~ /Skills\.(?:magicitemuse|arancesymbols)/
            skills.each { |skill_name| formula.gsub!(skill_name, "SpellRanks['#{options[:caster]}'].arcanesymbols.to_i") }
          end
        else
          skills.each { |skill_name| formula.gsub!(skill_name, "SpellRanks[#{options[:caster].to_s.inspect}].#{skill_name.sub(/^(?:Spells|Skills)\./, '')}.to_i") }
        end
      else
        if options[:target] and (options[:target] !~ /^(?:self|#{XMLData.name})$/i)
          formula = @duration['target'][:duration].dup || @duration['self'][:duration].to_s.dup
        else
          formula = @duration['self'][:duration].to_s.dup
        end
        if options[:activator] =~ /^(#{activator_modifier.keys.join('|')})$/i
          if formula =~ can_haz_spell_ranks
            skills.each { |skill_name| formula.gsub!(skill_name, "(Skills.magicitemuse * #{activator_modifier[options[:activator]]}).to_i") }
            formula = "(#{formula})/2.0"
          elsif formula =~ /Skills\.(?:magicitemuse|arancesymbols)/
            skills.each { |skill_name| formula.gsub!(skill_name, "(Skills.magicitemuse * #{activator_modifier[options[:activator]]}).to_i") }
          end
        elsif options[:activator] =~ /^(invoke|scroll)$/i
          if formula =~ can_haz_spell_ranks
            skills.each { |skill_name| formula.gsub!(skill_name, "Skills.arcanesymbols.to_i") }
            formula = "(#{formula})/2.0"
          elsif formula =~ /Skills\.(?:magicitemuse|arancesymbols)/
            skills.each { |skill_name| formula.gsub!(skill_name, "Skills.arcanesymbols.to_i") }
          end
        end
      end
      formula.untaint
      formula
    end

    def time_per(options={})
      formula = self.time_per_formula(options)
      proc { eval(formula) }.call.to_f
    end

    def timeleft=(val)
      #$stdout << "sess=%s spell=%s timeleft=%s\ntrace:\n%s\n" % [Session.current.name, self.num, val, Thread.current.backtrace.join("\n")]
      Session.current.spells.tracking.tap {|tracking|
        return tracking.delete(self.num) if val.eql?(0)
        tracking[self.num] = Time.now + val
      }
    end

    def timeleft
      sess = Session.current
      fail "cannot determine timeleft without a session" if sess.nil?
      return Spellsong.timeleft if self.time_per_formula.to_s == 'Spellsong.timeleft'
      duration = sess.spells.tracking[self.num]
      return 0 if duration.nil?
      [duration - Time.now, 0].max
    end

    def minsleft
      self.timeleft
    end

    def secsleft
      self.timeleft * 60
    end

    def active?
      self.timeleft > 0
    end

    def stackable?(options={})
      if options[:caster] and (options[:caster] !~ /^(?:self|#{XMLData.name})$/i)
        if options[:target] and (options[:target].downcase == options[:caster].downcase)
          @duration['self'][:stackable]
        else
          if @duration['target'][:stackable].nil?
            @duration['self'][:stackable]
          else
            @duration['target'][:stackable]
          end
        end
      else
        if options[:target] and (options[:target] !~ /^(?:self|#{XMLData.name})$/i)
          if @duration['target'][:stackable].nil?
            @duration['self'][:stackable]
          else
            @duration['target'][:stackable]
          end
        else
          @duration['self'][:stackable]
        end
      end
    end

    def refreshable?(options={})
      if options[:caster] and (options[:caster] !~ /^(?:self|#{XMLData.name})$/i)
        if options[:target] and (options[:target].downcase == options[:caster].downcase)
          @duration['self'][:refreshable]
        else
          if @duration['target'][:refreshable].nil?
            @duration['self'][:refreshable]
          else
            @duration['target'][:refreshable]
          end
        end
      else
        if options[:target] and (options[:target] !~ /^(?:self|#{XMLData.name})$/i)
          if @duration['target'][:refreshable].nil?
            @duration['self'][:refreshable]
          else
            @duration['target'][:refreshable]
          end
        else
          @duration['self'][:refreshable]
        end
      end
    end

    def multicastable?(options={})
      if options[:caster] and (options[:caster] !~ /^(?:self|#{XMLData.name})$/i)
        if options[:target] and (options[:target].downcase == options[:caster].downcase)
          @duration['self'][:multicastable]
        else
          if @duration['target'][:multicastable].nil?
            @duration['self'][:multicastable]
          else
            @duration['target'][:multicastable]
          end
        end
      else
        if options[:target] and (options[:target] !~ /^(?:self|#{XMLData.name})$/i)
          if @duration['target'][:multicastable].nil?
            @duration['self'][:multicastable]
          else
            @duration['target'][:multicastable]
          end
        else
          @duration['self'][:multicastable]
        end
      end
    end

    def known?
      if @num.to_s.length == 3
        circle_num = @num.to_s[0..0].to_i
      elsif @num.to_s.length == 4
        circle_num = @num.to_s[0..1].to_i
      else
        return false
      end
      if circle_num == 1
        ranks = [ Spells.minorspiritual || 0, XMLData.level ].min
      elsif circle_num == 2
        ranks = [ Spells.majorspiritual || 0, XMLData.level ].min
      elsif circle_num == 3
        ranks = [ Spells.cleric || 0, XMLData.level ].min
      elsif circle_num == 4
        ranks = [ Spells.minorelemental || 0, XMLData.level ].min
      elsif circle_num == 5
        ranks = [ Spells.majorelemental || 0, XMLData.level ].min
      elsif circle_num == 6
        ranks = [ Spells.ranger || 0, XMLData.level ].min
      elsif circle_num == 7
        ranks = [ Spells.sorcerer || 0, XMLData.level ].min
      elsif circle_num == 9
        ranks = [ Spells.wizard || 0, XMLData.level ].min
      elsif circle_num == 10
        ranks = [ Spells.bard || 0, XMLData.level ].min
      elsif circle_num == 11
        ranks = [ Spells.empath || 0, XMLData.level ].min
      elsif circle_num == 12
        ranks = [ Spells.minormental || 0, XMLData.level ].min
      elsif circle_num == 16
        ranks = [ Spells.paladin || 0, XMLData.level ].min
      elsif circle_num == 17
        if (@num == 1700) and (Char.prof =~ /^(?:Wizard|Cleric|Empath|Sorcerer|Savant)$/)
          return true
        else
          return false
        end
      elsif (circle_num == 97) and (Society.status == 'Guardians of Sunfist')
        ranks = Society.rank
      elsif (circle_num == 98) and (Society.status == 'Order of Voln')
        ranks = Society.rank
      elsif (circle_num == 99) and (Society.status == 'Council of Light')
        ranks = Society.rank
      elsif (circle_num == 96)
        if CMan[@name].to_i > 0
          return true
        else
          return false
        end
      else
        return false
      end
      if (@num % 100) <= ranks
        return true
      else
        return false
      end
    end

    def available?(options={})
      if self.known?
        if options[:caster] and (options[:caster] !~ /^(?:self|#{XMLData.name})$/i)
          if options[:target] and (options[:target].downcase == options[:caster].downcase)
            true
          else
            @availability == 'all'
          end
        else
          if options[:target] and (options[:target] !~ /^(?:self|#{XMLData.name})$/i)
            @availability == 'all'
          else
            true
          end
        end
      else
        false
      end
    end

    def to_s
      @name.to_s
    end

    def inspect()
      to_s
    end

    def active=(val)
      if ENV["DEBUG"]
        puts "%s\n%s" % ["Spell.active= is deprecated", Thread.current.backtrace.join("\n")]
      end
    end

    def max_duration(options={})
      if options[:caster] and (options[:caster] !~ /^(?:self|#{XMLData.name})$/i)
        if options[:target] and (options[:target].downcase == options[:caster].downcase)
          @duration['self'][:max_duration]
        else
          @duration['target'][:max_duration] || @duration['self'][:max_duration]
        end
      else
        if options[:target] and (options[:target] !~ /^(?:self|#{XMLData.name})$/i)
          @duration['target'][:max_duration] || @duration['self'][:max_duration]
        else
          @duration['self'][:max_duration]
        end
      end
    end

    def putup(options={})
      if stackable?(options)
        self.timeleft = [ self.timeleft + self.time_per(options), self.max_duration(options) ].min
      else
        self.timeleft = [ self.time_per(options), self.max_duration(options) ].min
      end
    end

    def putdown
      self.timeleft = 0
    end

    def remaining
      self.timeleft.as_time
    end

    def affordable?(options={})
      # fixme: deal with them dirty bards!
      release_options = options.dup
      release_options[:multicast] = nil
      if (self.mana_cost(options) > 0) and (  !checkmana(self.mana_cost(options)) or (Spell[515].active? and !checkmana(self.mana_cost(options) + [self.mana_cost(release_options)/4, 1].max))  )
        false
      elsif (self.stamina_cost(options) > 0) and (Spell[9699].active? or not checkstamina(self.stamina_cost(options)))
        false
      elsif (self.spirit_cost(options) > 0) and not checkspirit(self.spirit_cost(options) + 1 + [ 9912, 9913, 9914, 9916, 9916, 9916 ].delete_if { |num| !Spell[num].active? }.length)
        false
      else
        true
      end
    end

    def cast(target=nil, results_of_interest=nil)
      # fixme: find multicast in target and check mana for it
      script = Script.current
      if @type.nil?
        echo "cast: spell missing type (#{@name})"
        sleep 0.1
        return false
      end
      unless (self.mana_cost <= 0) or checkmana(self.mana_cost)
        echo 'cast: not enough mana'
        sleep 0.1
        return false
      end
      unless (self.spirit_cost > 0) or checkspirit(self.spirit_cost + 1 + [ 9912, 9913, 9914, 9916, 9916, 9916 ].delete_if { |num| !Spell[num].active? }.length)
        echo 'cast: not enough spirit'
        sleep 0.1
        return false
      end
      unless (self.stamina_cost <= 0) or checkstamina(self.stamina_cost)
        echo 'cast: not enough stamina'
        sleep 0.1
        return false
      end

      begin
        save_want_downstream = script.want_downstream
        save_want_downstream_xml = script.want_downstream_xml
        script.want_downstream = true
        script.want_downstream_xml = false
        @@cast_lock.push(script)
        until (@@cast_lock.first == script) or @@cast_lock.empty?
          sleep 0.1
          Script.current # allows this loop to be paused
          @@cast_lock.delete_if { |s| s.paused? or not Script.list.include?(s) }
        end
        unless (self.mana_cost <= 0) or checkmana(self.mana_cost)
          echo 'cast: not enough mana'
          sleep 0.1
          return false
        end
        unless (self.spirit_cost > 0) or checkspirit(self.spirit_cost + 1 + [ 9912, 9913, 9914, 9916, 9916, 9916 ].delete_if { |num| !Spell[num].active? }.length)
          echo 'cast: not enough spirit'
          sleep 0.1
          return false
        end
        unless (self.stamina_cost <= 0) or checkstamina(self.stamina_cost)
          echo 'cast: not enough stamina'
          sleep 0.1
          return false
        end
        if @cast_proc
          waitrt?
          waitcastrt?
          unless (self.mana_cost <= 0) or checkmana(self.mana_cost)
            echo 'cast: not enough mana'
            sleep 0.1
            return false
          end
          unless (self.spirit_cost > 0) or checkspirit(self.spirit_cost + 1 + [ 9912, 9913, 9914, 9916, 9916, 9916 ].delete_if { |num| !Spell[num].active? }.length)
            echo 'cast: not enough spirit'
            sleep 0.1
            return false
          end
          unless (self.stamina_cost <= 0) or checkstamina(self.stamina_cost)
            echo 'cast: not enough stamina'
            sleep 0.1
            return false
          end
          begin
            proc { eval(@cast_proc) }.call
          rescue
            echo "cast: error: #{$!}"
            respond $!.backtrace[0..2]
            return false
          end
        else
          if @channel
            cast_cmd = 'channel'
          else
            cast_cmd = 'cast'
          end
          if (target.nil? or target.to_s.empty?) and not @no_incant
            cast_cmd = "incant #{@num}"
          elsif (target.nil? or target.to_s.empty?) and (@type =~ /attack/i) and not [410,435,525,912,909,609].include?(@num)
            cast_cmd += ' target'
          elsif target.class == GameObj
            cast_cmd += " ##{target.id}"
          elsif target.class == Fixnum
            cast_cmd += " ##{target}"
          else
            cast_cmd += " #{target}"
          end
          cast_result = nil
          loop {
            waitrt?
            if cast_cmd =~ /^incant/
              if (checkprep != @name) and (checkprep != 'None')
                dothistimeout 'release', 5, /^You feel the magic of your spell rush away from you\.$|^You don't have a prepared spell to release!$/
              end
            else
              unless checkprep == @name
                unless checkprep == 'None'
                  dothistimeout 'release', 5, /^You feel the magic of your spell rush away from you\.$|^You don't have a prepared spell to release!$/
                  unless (self.mana_cost <= 0) or checkmana(self.mana_cost)
                    echo 'cast: not enough mana'
                    sleep 0.1
                    return false
                  end
                  unless (self.spirit_cost <= 0) or checkspirit(self.spirit_cost + 1 + (if checkspell(9912) then 1 else 0 end) + (if checkspell(9913) then 1 else 0 end) + (if checkspell(9914) then 1 else 0 end) + (if checkspell(9916) then 5 else 0 end))
                    echo 'cast: not enough spirit'
                    sleep 0.1
                    return false
                  end
                  unless (self.stamina_cost <= 0) or checkstamina(self.stamina_cost)
                    echo 'cast: not enough stamina'
                    sleep 0.1
                    return false
                  end
                end
                loop {
                  waitrt?
                  waitcastrt?
                  prepare_result = dothistimeout "prepare #{@num}", 8, /^You already have a spell readied!  You must RELEASE it if you wish to prepare another!$|^Your spell(?:song)? is ready\.|^You can't think clearly enough to prepare a spell!$|^You are concentrating too intently .*?to prepare a spell\.$|^You are too injured to make that dextrous of a movement|^The searing pain in your throat makes that impossible|^But you don't have any mana!\.$|^You can't make that dextrous of a move!$|^As you begin to prepare the spell the wind blows small objects at you thwarting your attempt\.$|^You do not know that spell!$|^All you manage to do is cough up some blood\.$|The incantations of countless spells swirl through your mind as a golden light flashes before your eyes\./
                  if prepare_result =~ /^Your spell(?:song)? is ready\./
                    break
                  elsif prepare_result == 'You already have a spell readied!  You must RELEASE it if you wish to prepare another!'
                    dothistimeout 'release', 5, /^You feel the magic of your spell rush away from you\.$|^You don't have a prepared spell to release!$/
                    unless (self.mana_cost <= 0) or checkmana(self.mana_cost)
                      echo 'cast: not enough mana'
                      sleep 0.1
                      return false
                    end
                  elsif prepare_result =~ /^You can't think clearly enough to prepare a spell!$|^You are concentrating too intently .*?to prepare a spell\.$|^You are too injured to make that dextrous of a movement|^The searing pain in your throat makes that impossible|^But you don't have any mana!\.$|^You can't make that dextrous of a move!$|^As you begin to prepare the spell the wind blows small objects at you thwarting your attempt\.$|^You do not know that spell!$|^All you manage to do is cough up some blood\.$|The incantations of countless spells swirl through your mind as a golden light flashes before your eyes\./
                    sleep 0.1
                    return prepare_result
                  end
                }
              end
            end
            waitcastrt?
            if @stance and checkstance != 'offensive'
              put 'stance offensive'
              # dothistimeout 'stance offensive', 5, /^You (?:are now in|move into) an? offensive stance|^You are unable to change your stance\.$/
            end
            if results_of_interest.class == Regexp
              results_regex = /^(?:Cast|Sing) Roundtime [0-9]+ Seconds?\.$|^Cast at what\?$|^But you don't have any mana!$|^\[Spell Hindrance for|^You don't have a spell prepared!$|keeps? the spell from working\.|^Be at peace my child, there is no need for spells of war in here\.$|Spells of War cannot be cast|^As you focus on your magic, your vision swims with a swirling haze of crimson\.$|^Your magic fizzles ineffectually\.$|^All you manage to do is cough up some blood\.$|^And give yourself away!  Never!$|^You are unable to do that right now\.$|^You feel a sudden rush of power as you absorb [0-9]+ mana!$|^You are unable to drain it!$|leaving you casting at nothing but thin air!$|^You don't seem to be able to move to do that\.$|^Provoking a GameMaster is not such a good idea\.$|^You can't think clearly enough to prepare a spell!$|^You do not currently have a target\.$|The incantations of countless spells swirl through your mind as a golden light flashes before your eyes\.|#{results_of_interest.to_s}/
            else
              results_regex = /^(?:Cast|Sing) Roundtime [0-9]+ Seconds?\.$|^Cast at what\?$|^But you don't have any mana!$|^\[Spell Hindrance for|^You don't have a spell prepared!$|keeps? the spell from working\.|^Be at peace my child, there is no need for spells of war in here\.$|Spells of War cannot be cast|^As you focus on your magic, your vision swims with a swirling haze of crimson\.$|^Your magic fizzles ineffectually\.$|^All you manage to do is cough up some blood\.$|^And give yourself away!  Never!$|^You are unable to do that right now\.$|^You feel a sudden rush of power as you absorb [0-9]+ mana!$|^You are unable to drain it!$|leaving you casting at nothing but thin air!$|^You don't seem to be able to move to do that\.$|^Provoking a GameMaster is not such a good idea\.$|^You can't think clearly enough to prepare a spell!$|^You do not currently have a target\.$|The incantations of countless spells swirl through your mind as a golden light flashes before your eyes\./
            end
              cast_result = dothistimeout cast_cmd, 5, results_regex
              if cast_result == "You don't seem to be able to move to do that."
                100.times { break if clear.any? { |line| line =~ /^You regain control of your senses!$/ }; sleep 0.1 }
                cast_result = dothistimeout cast_cmd, 5, results_regex
              end
              if @stance
                if @@after_stance
                  if checkstance !~ /#{@@after_stance}/
                    waitrt?
                    dothistimeout "stance #{@@after_stance}", 3, /^You (?:are now in|move into) an? \w+ stance|^You are unable to change your stance\.$/
                  end
                elsif checkstance !~ /^guarded$|^defensive$/
                  waitrt?
                  if checkcastrt > 0
                    dothistimeout 'stance guarded', 3, /^You (?:are now in|move into) an? \w+ stance|^You are unable to change your stance\.$/
                  else
                    dothistimeout 'stance defensive', 3, /^You (?:are now in|move into) an? \w+ stance|^You are unable to change your stance\.$/
                  end
                end
              end
              if cast_result =~ /^Cast at what\?$|^Be at peace my child, there is no need for spells of war in here\.$|^Provoking a GameMaster is not such a good idea\.$/
                dothistimeout 'release', 5, /^You feel the magic of your spell rush away from you\.$|^You don't have a prepared spell to release!$/
              end
              break unless (@circle.to_i == 10) and (cast_result =~ /^\[Spell Hindrance for/)
              }
              cast_result
        end
      ensure
        script.want_downstream = save_want_downstream
        script.want_downstream_xml = save_want_downstream_xml
        @@cast_lock.delete(script)
      end
    end

    def _bonus
      @bonus.dup
    end

    def _cost
      @cost.dup
    end

    def clear_on_death
      !@persist_on_death
    end

    def circle
      id = @num.to_s
      case id.size
      when 3
        id[0]
      when 4
        id.slice(0..2)
      end
    end

    def msgdown
      @msgdn
    end
  end
end
