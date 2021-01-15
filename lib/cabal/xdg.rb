require "xdg"
require "yaml"

module Cabal::XDG
  @root   = "cabal"
  @config = ::XDG::Config.new

  def self.app()
    @config.home.join(@root)
  end

  def self.path(*args)
    return app if args.empty?
    app.join(*args)
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
    FileUtils.touch(file)
    file
  end

  def self.exist?(*args)
    File.exist? self.path.join(*args)
  end

  def self.accounts()
    this = Cabal::XDG.yaml("accounts") || {}
    return this unless block_given?
    yield(this)
    File.open(self.path("accounts.yaml"), 'w') { |f|
      f.write this.to_yaml
    }
  end

  def self.account_for(character)
    accounts.find {|account_name, account_info|
      account_info["characters"].map(&:downcase).include?(character.downcase)
    }
  end
end
