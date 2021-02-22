require 'urnon/util/sessionize'
require 'urnon/spells/registry'
require 'urnon/spells/record'
require 'urnon/spells/spell-song'

class Spells
  extend Sessionize.new receiver: :spells

  attr_accessor :session, :tracking,
                :minorelemental, :minormental, :minorspiritual,
                :majorelemental, :majorspiritual,
                :wizard , :sorcerer , :ranger , :paladin , :empath , :cleric , :bard

  def initialize(session)
    self.instance_variables.each do |var| self.instance_variable_set(var, 0) end
    @session = session
    @tracking  = {}
    self.load
  end

  def [](query)
    Spells::Registry.query(query)
  end

  def load()
    Spells::Registry.load()
  end

  def serialize
    [ @minorelemental,@majorelemental,@minorspiritual,@majorspiritual,@wizard,
      @sorcerer,@ranger,@paladin,@empath,@cleric,@bard,@minormental]
  end

  def load_serialized=(val)
    (@minorelemental,@majorelemental,@minorspiritual,@majorspiritual,
    @wizard,@sorcerer,@ranger,@paladin,@empath,@cleric,@bard,@minormental = val)
  end

  def upmsgs()
    self.list.map(&:msgup)
  end

  def dnmsgs()
    self.list.map(&:msgdown)
  end

  def list()
    Spells::Registry.spells
  end

  def known
    self.list.select(&:known?)
  end

  def active
    @tracking
      .select {|num, expiry| expiry > Time.now }
      .map {|num, expiry| Spell[num] }
  end
end

# todo: remove this
Spell = Spells
