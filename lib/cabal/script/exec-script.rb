

class ExecScript < Script
  def self.id()
    Script.atomic {
      num = '1'; num.succ! while Script.running.any? { |s| s.is_a?(ExecScript) && s.id == num }
      return num
    }
  end

  def self.start(...)
    self.new(...)
  end

  attr_reader :contents, :id
  def initialize(contents, opts={})
    @id   = ExecScript.id()
    @name = "exec/#{@id}"
    super(opts.merge({name: @name, file_name: @name})) { |script|
      runtime = GLOBAL_SCRIPT_CONTEXT.dup
      runtime.local_variable_set :script, script
      runtime.local_variable_set :context, runtime
      runtime.eval(contents, script.name)
    }
  end
end
