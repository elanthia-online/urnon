module Util
  def self.trace(msg = "")
    begin
      raise Exception.new(msg)
    rescue => e
      $stderr.puts "Util.trace::message:\n%s\ntimestamp:%s\nbacktrace:\n%s\n" % [
        e.message,
        Time.now,
        e.backtrace.slice(1).join("\n")
        ]
    end
  end
end
