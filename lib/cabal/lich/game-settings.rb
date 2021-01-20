require 'cabal/session'

module GameSetting
  def GameSetting.load(*args)
     Setting.load(args.collect { |a| "#{Session.current.xml_data.game}:#{a}" })
  end
  def GameSetting.save(hash)
     game_hash = Hash.new
     hash.each_pair { |k,v| game_hash["#{Session.current.xml_data.game}:#{k}"] = v }
     Setting.save(game_hash)
  end
end

module CharSetting
  def CharSetting.load(*args)
     Setting.load(args.collect { |a| "#{Session.current.xml_data.game}:#{Session.current.xml_data.name}:#{a}" })
  end
  def CharSetting.save(hash)
     game_hash = Hash.new
     hash.each_pair { |k,v| game_hash["#{Session.current.xml_data.game}:#{Session.current.xml_data.name}:#{k}"] = v }
     Setting.save(game_hash)
  end
end

module GameSettings
  def GameSettings.[](name)
     Settings.to_hash(Session.current.xml_data.game)[name]
  end
  def GameSettings.[]=(name, value)
     Settings.to_hash(Session.current.xml_data.game)[name] = value
  end
  def GameSettings.to_hash
     Settings.to_hash(Session.current.xml_data.game)
  end
end
