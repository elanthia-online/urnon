module Urnon
  module Escape
    def self.to_front_end(str)
      str.gsub("<", "&lt;")
    end
  end
end
