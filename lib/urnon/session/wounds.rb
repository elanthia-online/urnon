require 'urnon/util/sessionize'

class Wounds
  extend Sessionize.new receiver: :wounds

  attr_reader :session
  def initialize(session)
    @session = session
  end

  def respond_to?(area)
    self.methods.include?(area)
  end

  def methods
    self.session.xml_data.injuries.keys.map {|area| area.gsub(/([A-Z])/) { "_%s" % $1.downcase }.to_sym } + super
  end

  def method_missing(area)
    # todo: maybe rename rightArm, rightLeg, etc in XMLParser?
    legacy_property_name = area.to_s.gsub(/_([a-z])/) { "%s" % $1.upcase }
    return super unless respond_to?(area)
    self.session.xml_data.injuries.dig(legacy_property_name, "wound")
  end
end
