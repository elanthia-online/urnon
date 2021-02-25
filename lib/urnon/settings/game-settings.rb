require 'urnon/session'
require 'urnon/script/script'
require 'urnon/util/sql-setting'

module GameSettings
  extend SqlSetting.new(table: :script_auto_settings) {
    sess   = Session.current or fail Exception, "#{self.name} cannot be used without a Session context"
    xml    = sess.xml_data or fail Exception, "Session did not have an xml_data parser"
    {scope: xml.game, script: File.basename(Script.current.name)}
  }
end
