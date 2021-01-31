require 'urnon/util/sessionize'
require 'urnon/map/cache'
require 'urnon/map/record'
require 'urnon/map/map'
require 'urnon/map/lich-api'

class Room
  extend Sessionize.new receiver: :room

  attr_reader :session
  def initialize(session)
    @session = session
  end

  def current()
    Map::Cache.current_room(@session)
  end

  def [](val)
    Map::Cache.fzf(val)
  end
end
