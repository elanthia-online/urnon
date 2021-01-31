module Package
  #
  # make is easy to load other scripts/deps 
  # relative to a running script on all platforms
  #
  def self.load(path)
    Kernel.load File.join(SCRIPT_DIR, path)
  end
end