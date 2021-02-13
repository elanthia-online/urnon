class StringProc
  def initialize(string)
    @string = string
    @string.untaint
  end

  def kind_of?(type)
    Proc.new {}.kind_of? type
  end

  def class
    Proc
  end

  def call(*a)
    proc { eval(@string) }.call
  end

  def _dump(d=nil)
    @string
  end

  def to_json(...)
    self.to_s
  end

  def to_s
    ";e #{_dump}"
  end

  def inspect
    "StringProc.new(#{@string.inspect})"
  end

  def StringProc._load(string)
    StringProc.new(string)
  end
end
