require 'urnon/util/sessionize'
require 'urnon/spells/registry'
require 'urnon/spells/record'
require 'urnon/spells/spell-song'

class Spells
  extend Sessionize.new receiver: :spells

  attr_reader :session

  def initialize(session)
    @session = session
  end

  def [](query)
    Spells::Registry.query(query)
  end
end

# todo: remove this
Spell = Spells
