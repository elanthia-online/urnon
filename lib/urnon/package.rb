require 'pathname'

module Package
  #
  # make is easy to load other scripts/deps
  # relative to a running script on all platforms
  #
  def self.load(path)
    script = Script.current.file_name
    relative_dir = script ? Pathname.new(script).dirname  : SCRIPT_DIR
    Kernel.load File.join(relative_dir, path)
  end
end
