##
## TODO: de-duplicate these definitions and
## 1. break them into their own files
## 2. merge them if they already exist
##
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

require_relative("./spell")

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