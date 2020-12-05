require "xdg"
require "yaml"

module Cabal::XDG
  @config = ::XDG::Config.new
  @data   = ::XDG::Data.new

  def self.config(*args)
    @config.home.join($0, *args)
  end

  def self.data(*args)
    @data.home.join($0, *args)
  end

  [config, data].each {|dir| FileUtils.mkdir_p(dir) }

  def self.yaml(file)
    YAML.load(
      File.read touch(file.to_s + ".yaml"),
      symbolize_names: true)
  end
  
  def self.touch(file)
    file = config.join(file)
    #pp file
    FileUtils.touch(file)
    file
  end

  def self.accounts()
    Cabal::XDG.yaml("accounts") || {}
  end

  def self.account_for(character)
    accounts.find {|account_name, account_info|
      account_info["characters"].map(&:downcase).include?(character.downcase)
    }
  end
end