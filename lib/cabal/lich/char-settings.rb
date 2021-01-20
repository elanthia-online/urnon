require 'cabal/session'

module CharSettings
   def CharSettings.[](name)
      Settings.to_hash("#{Session.current.xml_data.game}:#{Session.current.xml_data.name}")[name]
   end
   def CharSettings.[]=(name, value)
      Settings.to_hash("#{Session.current.xml_data.game}:#{Session.current.xml_data.name}")[name] = value
   end
   def CharSettings.to_hash
      Settings.to_hash("#{Session.current.xml_data.game}:#{Session.current.xml_data.name}")
   end
   def CharSettings.save()
      Settings.save()
   end
   def CharSettings.load()
      put "CharSettings.load() is deprecated, they are loaded automagically now."
      :noop
   end
end
