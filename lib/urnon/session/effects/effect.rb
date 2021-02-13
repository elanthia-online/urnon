require 'urnon/effects/effects'

module Effects
  class Effect
    def initialize(&block)
      self.instance_exec(&block)
    end
  end
end
