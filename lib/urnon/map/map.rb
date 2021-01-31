require 'urnon/map/cache'

module Map
  def self.method_missing(...)
    Map::Cache.load()
    Map::Cache.send(...)
  end
end
