require 'urnon/util/sessionize'

class Char
  extend Sessionize.new receiver: :char

  def self.name()
    receiver.name
  end

  attr_accessor :citizenship
  attr_reader :session

  def initialize(session)
    @session = session
    @citizenship ||= nil
    attach_proxies
  end

  def name
    session.xml_data.name
  end

  def attach_proxies()
    proxies.slice(0..1).each do |interface|
      proxy_methods = interface.methods - self.methods
      proxy_methods.each do |method_name|
        (class << self; self; end).class_eval do
          self.define_method(method_name) do |*args|
            interface.method(method_name).call(*args)
          end
        end
      end
    end
  end

  def proxies
    [@session.stats, @session.skills, @session.society]
  end

=begin
  def respond_to?(method)
    proxies.any? {|interface|
      interface.respond_to?(method)
    }
  end

  def method_missing(method, *args)
    return unless self.respond_to?(method)
    impl = proxies.find {|interface| interface.respond_to?(method)}
    impl.send(method, *args)
  end
=end

  %i(health mana spirit stamina).each do |prop|
    # checkmana, checkstamina, etc
    define_method(prop) do
      return session.xml_data.send(prop)
    end
    # max_health, max_mana, etc
    define_method("max_%s" % prop) do
      session.xml_data.send("max_%s" % prop)
    end
    # percent_health, percent_mana, etc
    define_method("percent_%s" % prop) do
      return ((session.xml_data.send(prop).to_f / session.xml_data.send("max_%s" % prop).to_f) * 100).to_i
    end
  end
end
