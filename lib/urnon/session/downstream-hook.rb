require 'urnon/util/format'
require 'urnon/util/sessionize'

class DownstreamHook
  extend Sessionize.new receiver: :downstream_hooks

  attr_reader :hooks, :session

  def initialize(session)
    @session = session
    @hooks   = Hash.new
  end

  def add(name, action, script = Script.current)
    raise Exception, "DownstreamHooks cannot be added with Scriptless contexts\ncontext=#{script.class.name}" unless script.is_a?(::Script)
    return self.hooks[name] = [action, script] if action.is_a?(Proc)
    raise Exception, "#{action.class.name} is not a Proc"
  end

  def run(server_string)
    for key in self.hooks.keys
      hook, script  = self.hooks[key]
      unless script.alive?
        self.hooks.delete(key)
        next
      end
      server_string = self.task(key, hook, script, server_string).value
      return nil if server_string.nil?
    end
    return server_string
  end

  def task(key, hook, script, server_string)
    Thread.new {
      begin
        original_string = server_string.dup
        Thread.current[:script]  = script
        Thread.current[:session] = self.session
        exec_time = Benchmark.realtime { server_string = hook.call(server_string.dup)}
        self.report_exec_time(key, exec_time)
      rescue Exception => e
        self.session.to_client <<~ERROR
          --- urnon: DownstreamstreamHook Error
            script=#{script.name}
              hook=#{key}
          location=#{hook.source_location}
            Error:
              #{e.message}
            Backtrace:
              #{e.backtrace.join("\n")}
        ERROR
        server_string = original_string
      end
      server_string
    }
  end

  def report_exec_time(key, exec_time)
    return if (exec_time * 1000) < 50 # milliseconds
    self.session.to_client "warning(downstreamhook::#{key}) took #{Format.time(exec_time)}"
  end

  def remove(name)
    self.hooks.delete(name)
  end

  def list
    self.hooks.keys.dup
  end
end
