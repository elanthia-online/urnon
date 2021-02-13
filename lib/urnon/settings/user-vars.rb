require 'urnon/session'
require 'urnon/util/sql-setting'

module UserVars
  extend SqlSetting.new(table: :uservars) {
    sess = Session.current or fail Exception, "Vars cannot be persisted without a valid Session context"
    xml = sess.xml_data or fail Exception, "Session did not have an xml_data parser"
    {scope: [xml.game, xml.name].join(":")}
  }
end
