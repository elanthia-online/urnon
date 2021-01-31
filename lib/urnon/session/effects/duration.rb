module Effects
  class Duration
    attr_reader :effect, :expiry

    def initialize(effect, seconds)
      @effect = effect
      @expiry = Time.now + seconds
    end

    def expired?
      Time.now > self.expiry
    end

    def remaining
      self.expiry - Time.now
    end
  end
end
