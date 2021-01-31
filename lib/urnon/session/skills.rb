require 'urnon/util/sessionize'

class Skills
  extend Sessionize.new receiver: :skills

  attr_accessor :twoweaponcombat,  :armoruse,  :shielduse,  :combatmaneuvers,
                :edgedweapons,  :bluntweapons,  :twohandedweapons,  :rangedweapons,
                :thrownweapons,  :polearmweapons,  :brawling,
                :ambush,  :multiopponentcombat,  :combatleadership,  :physicalfitness,  :dodging,
                :arcanesymbols,  :magicitemuse,  :spellaiming,  :harnesspower,  :emc,  :mmc,  :smc,
                :elair,  :elearth,  :elfire,  :elwater,
                :slblessings,  :slreligion,  :slsummoning,  :sldemonology,  :slnecromancy,  :mldivination,
                :mlmanipulation,  :mltelepathy,  :mltransference,  :mltransformation,
                :survival,  :disarmingtraps,  :pickinglocks,  :stalkingandhiding,
                :perception,  :climbing,  :swimming,  :firstaid,  :trading,  :pickpocketing

  attr_reader :session

  def initialize(session)
    self.instance_variables.each do |var| self.instance_variable_set(var, 0) end
    @session = session
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
