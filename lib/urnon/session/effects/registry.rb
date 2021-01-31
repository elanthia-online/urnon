
module Effects
  class Registry
    include Enumerable

    attr_reader :session
    def initialize(session)
      @session = session
    end
  end
end
