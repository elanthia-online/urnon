require "xdg"
require "yaml"

module Cabal::XDG
  @root   = "cabal"
  @config = ::XDG::Config.new

  def self.path(*args)
    @config.home.join(@root, *args)
  end

  def self.scripts()
    path.join("scripts")
  end

  def self.data()
    path.join("data")
  end

  def self.yaml(file)
    YAML.load(
      File.read touch(file.to_s + ".yaml"),
      symbolize_names: true)
  end
  
  def self.touch(file)
    file = path.join(file)
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