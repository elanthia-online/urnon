class SynchronizedSocket
  def initialize(o)
     @delegate = o
     @mutex = Mutex.new
     self
  end
  def puts(*args, &block)
     @mutex.synchronize {
        @delegate.puts *args, &block
     }
  end
  def write(*args, &block)
     @mutex.synchronize {
        @delegate.write *args, &block
     }
  end
  def method_missing(method, *args, &block)
     @delegate.__send__ method, *args, &block
  end
end