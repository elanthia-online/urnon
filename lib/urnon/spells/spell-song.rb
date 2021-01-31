module Spellsong
  def self.cost
    self.renew_cost
  end

  def self.tonis_dodge_bonus
    thresholds = [1,2,3,5,8,10,14,17,21,26,31,36,42,49,55,63,70,78,87,96]
    bonus = 20
    thresholds.each { |val| if Skills.elair >= val then bonus += 1 end }
    bonus
  end

  def self.mirrors_dodge_bonus
    20 + ((Spells.bard - 19) / 2).round
  end

  def self.mirrors_cost
    [19 + ((Spells.bard - 19) / 5).truncate, 8 + ((Spells.bard - 19) / 10).truncate]
  end

  def self.sonic_bonus
    (Spells.bard / 2).round
  end

  def self.sonic_armor_bonus
    self.sonic_bonus + 15
  end

  def self.sonic_blade_bonus
    self.sonic_bonus + 10
  end

  def self.sonic_weapon_bonus
    self.sonicbladebonus
  end

  def self.sonic_shield_bonus
    self.sonic_bonus + 10
  end

  def self.valor_bonus
    10 + (([Spells.bard, Stats.level].min - 10) / 2).round
  end

  def self.valor_cost
    [10 + (self.valor_bonus / 2), 3 + (self.valor_bonus / 5)]
  end

  def self.luck_cost
    [6 + ((Spells.bard - 6) / 4),(6 + ((Spells.bard - 6) / 4) / 2).round]
  end

  def self.mana_cost
    [18,15]
  end

  def self.fort_cost
    [3,1]
  end

  def self.shield_cost
    [9,4]
  end

  def self.weapon_cost
    [12,4]
  end

  def self.armor_cost
    [14,5]
  end

  def self.sword_cost
    [25,15]
  end
end
