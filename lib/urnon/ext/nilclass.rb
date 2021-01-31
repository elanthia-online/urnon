class NilClass
  def dup
    nil
  end
  def method_missing(method, *args)
    Util.trace("NilClass:undefined_method method=#{method} args=#{args}") if ENV["DEBUG"]
    nil
  end
  def split(*val)
    Array.new
  end
  def to_s
    ""
  end
  def strip
    ""
  end
  def +(val)
    val
  end
  def closed?
    true
  end
end
