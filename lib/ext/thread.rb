class Thread
  alias_method :_initialize, :initialize

  def initialize(*args, &block)
    @_parent = Thread.current if defined?(Script) && Thread.current.is_a?(Script)
    _initialize(*args, &block)
  end

  def parent()
    @_parent
  end

  def child_threads()
    Thread.list.select {|thread| thread.parent.eql? self }
  end

  def dispose()
    @_parent = nil
  end
end
