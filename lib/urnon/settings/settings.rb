require 'urnon/session'
require 'urnon/script/script'
require 'urnon/util/sql-setting'

module Settings
  extend SqlSetting.new(table: :script_auto_settings) {
    script = Script.current or fail Exception, "#{self.name} cannot be used outside of the Script context"
    sess   = Session.current or fail Exception, "#{self.name} cannot be used without a Session context"
    xml    = sess.xml_data or fail Exception, "Session did not have an xml_data parser"
    {script: Script.current.name, scope: [xml.game, xml.name].join(":")}
  }
end
