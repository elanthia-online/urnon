require 'urnon/util/sessionize'

class Spells
  extend Sessionize.new receiver: :spells

  attr_reader :session

  def initialize(session)
    @session = session
  end

  def [](query)
    Spell.of(session, query)
  end
end

# todo: remove this
Spell = Spells
