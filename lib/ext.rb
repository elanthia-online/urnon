class NilClass
  def dup
    nil
  end
  def method_missing(method, *args)
    return nil unless ENV["DEBUG"]
    begin
      raise "NilClass:undefined_method method=#{method} args=#{args}"
    rescue => e
      $stderr.puts "Message: %s\nTimestamp:%s\nBacktrace:\n%s\n" % [
        e.message,
        Time.now,
        e.backtrace.join("\n")
        ]
    end
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

class Numeric
  def as_time
     sprintf("%d:%02d:%02d", (self / 60).truncate, self.truncate % 60, ((self % 1) * 60).truncate)
  end
  def with_commas
     self.to_s.reverse.scan(/(?:\d*\.)?\d{1,3}-?/).join(',').reverse
  end
end

class String
  def to_s
     self.dup
  end

  def stream
     @stream
  end

  def stream=(val)
     @stream ||= val
  end
end

##
## needed to Script subclass
##
require_relative("./script")

class Thread
  alias_method :_initialize, :initialize

  def initialize(*args, &block)
    @_parent = Thread.current if Thread.current.is_a?(Script)
    _initialize(*args, &block)
  end

  def parent
    @_parent
  end

  def dispose()
    @_parent = nil
  end
end


class String
   def to_a # for compatibility with Ruby 1.8
      [self]
   end
   def silent
      false
   end
   def split_as_list
      string = self
      string.sub!(/^You (?:also see|notice) |^In the .+ you see /, ',')
      string.sub('.','')
        .sub(/ and (an?|some|the)/, ', \1')
        .split(',')
        .reject { |str| str.strip.empty? }
        .collect { |str| str.lstrip }
   end
end
