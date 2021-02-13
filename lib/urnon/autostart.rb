require "yaml"
require "urnon/xdg"
require 'urnon/script/runtime'

module Autostart
  def self.yaml_autostart(session)
    launch_global_yaml(session)
    launch_character_yaml(session)
  end

  def self.load_yaml(file)
    file = Urnon::XDG.path.join(file)
    return {} unless File.exists? file
    YAML.load File.read(file)
  end

  def self.yaml?
    Dir.exists? Urnon::XDG.path("autostart")
  end

  def self.start(session, script)
    (script, *argv)= script.strip.split(/\s+/)
    return if Script.running?(script)
    return unless Script.exists?(script)
    Script.start(script, argv.join(" "), session: session)
    ttl = Time.now + 3
    sleep 0.1 until Script.running?(script) or Time.now > ttl
    respond "autostart: error: #{script} failed to start" if Time.now > ttl
  end

  def self.launch_global_yaml(session)
    profile = load_yaml "autostart/_global.yaml"
    profile.fetch("gems", []).each do |gem|
      begin
        require(gem)
      rescue Exception => err
        puts err.message
        puts err.backtrace
      end
    end
    profile.fetch("scripts", []).each do |script| Autostart.start(session, script) end
  end

  def self.launch_character_yaml(session)
    profile = load_yaml "autostart/#{session.name.downcase}.yaml"
    profile.fetch("scripts", []).each do |script| Autostart.start(session, script) end
  end

  def self.autostart_lich_script(session)
    return Script.start("autostart", session: session) if Script.exists?("autostart")
  end

  def self.call(session)
    begin
      sleep 0.1 while session.xml_data.name.empty?
      return yaml_autostart(session) if yaml?
      autostart_lich_script(session)
    rescue => exception
      puts exception.message
      puts exception.backtrace.join("\n")
    end
  end
end
