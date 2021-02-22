require 'urnon/script/script'

class ExecScript < Script
  def self.start(...)
    self.new(...)
  end

  attr_reader :contents, :id
  def initialize(contents, opts={})
    scripts = opts.fetch(:session).scripts
    scripts.tap {|scripts|
      scripts.atomic {
        num = '1'; num.succ! while scripts.running.any? { |s| s.is_a?(ExecScript) && s.id == num }
        @id = num
      }
    }
    @name = "exec/#{@id}"
    super(opts.merge({name: @name, file_name: @name})) { |script|
      scripts.runtime(script.session)
            .eval(contents, script.name)
    }
  end
end
