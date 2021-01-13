require "yaml"
require_relative "./xdg"

module Autostart
  def self.yaml_autostart()
    launch_global_yaml
    launch_character_yaml
  end

  def self.load_yaml(file)
    file = Cabal::XDG.path.join(file)
    return {} unless File.exists? file
    YAML.load File.read(file)
  end

  def self.yaml?
    Dir.exists? Cabal::XDG.path("autostart")
  end

  def self.start(script)
    (script, *argv)= script.strip.split(/\s+/)
    return if Script.running?(script)
    return unless Script.exists?(script)
    Script.start(script, argv.join(" "))
    ttl = Time.now + 3
    sleep 0.1 until Script.running?(script) or Time.now > ttl
    respond "autostart: error: #{script} failed to start" if Time.now > ttl
  end

  def self.launch_global_yaml()
    profile = load_yaml "autostart/_global.yaml"
    profile.fetch("gems", []).each do |gem| require(gem) end
    profile.fetch("scripts", []).each do |script| Autostart.start(script) end
  end

  def self.launch_character_yaml()
    profile = load_yaml "autostart/#{XMLData.name.downcase}.yaml"
    profile.fetch("scripts", []).each do |script| Autostart.start(script) end
  end

  def self.autostart_lich_script()
    return Script.start("autostart") if Script.exists?("autostart")
  end

  def self.call()
    wait_until { XMLData.name.is_a?(String) }
    return yaml_autostart if yaml?
    autostart_lich_script
  end
end
