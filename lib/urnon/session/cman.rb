require 'urnon/util/sessionize'

class CMan
  extend Sessionize.new receiver: :cman

  attr_reader   :session
  attr_accessor :armor_spike_focus, :bearhug, :berserk, :block_mastery, :bull_rush,
                :burst_of_swiftness, :charge, :cheapshots, :combat_focus, :combat_mastery,
                :combat_mobility, :combat_movement, :combat_toughness, :coup_de_grace,
                :crowd_press, :cunning_defense, :cutthroat, :dirtkick, :disarm_weapon,
                :divert, :duck_and_weave, :dust_shroud, :evade_mastery, :executioners_stance,
                :feint, :flurry_of_blows, :garrote, :grapple_mastery, :griffins_voice, :groin_kick,
                :hamstring, :haymaker, :headbutt, :inner_harmony, :internal_power, :ki_focus,
                :kick_mastery, :mighty_blow, :multi_fire, :mystic_strike, :parry_mastery,
                :perfect_self, :precision, :predators_eye, :punch_mastery, :quickstrike,
                :rolling_krynch_stance, :shadow_mastery, :shield_bash, :shield_charge,
                :side_by_side, :silent_strike, :slippery_mind,
                :specialization_i, :specialization_ii, :specialization_iii,
                :spell_cleaving, :spell_parry, :spell_thieve, :spin_attack, :staggering_blow,
                :stance_of_the_mongoose, :striking_asp, :stun_maneuvers, :subdual_strike,
                :subdue, :sucker_punch, :sunder_shield, :surge_of_strength, :sweep,
                :tackle, :tainted_bond, :trip, :truehand, :twin_hammerfists, :unarmed_specialist,
                :weapon_bonding, :vanish, :whirling_dervish,

  def initialize(session)
    @session = session
  end

  def [](name)
    self.send(name.gsub(/[\s\-]/, '_').gsub("'", "").downcase)
  end

  def []=(name,val)
    CMan.send("#{name.gsub(/[\s\-]/, '_').gsub("'", "").downcase}=", val.to_i)
  end
end
