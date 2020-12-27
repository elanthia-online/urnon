

class ExecScript < Script
  def self.id()
    Script.atomic {
      num = '1'; num.succ! while Script.running.any? { |s| s.is_a?(ExecScript) && s.id == num }
      return num
    }
  end
  
  def self.start(contents, options={})
    options = { :quiet => true } if options == true
    self.new(contents, options)
  end

  attr_reader :contents, :id
  def initialize(contents, flags=Hash.new)
    @id   = ExecScript.id()
    @name = "exec/#{@id}"
    super(name: @name, file_name: @name) { |script|
      runtime = SCRIPT_CONTEXT.dup
      runtime.local_variable_set :script, script
      runtime.local_variable_set :context, runtime
      runtime.eval(contents, script.name)
    }
  end
end