require 'urnon/util/format'
require 'urnon/util/sessionize'

class UpstreamHook
  extend Sessionize.new receiver: :upstream_hooks

  attr_reader :hooks, :session

  def initialize(session)
    @session = session
    @hooks   = Hash.new
  end

  def add(name, action, script = Script.current)
    raise Exception, "UpstreamHooks cannot be added with Scriptless contexts\ncontext=#{script.class.name}" unless script.is_a?(::Script)
    raise Exception, "#{action.class.name} is not a Proc" unless action.is_a?(Proc)
    return self.hooks[name] = [action, script]
  end

  def run(client_string)
    for key in self.hooks.keys
      hook, script = self.hooks[key]
      unless script.alive?
        self.hooks.delete(key)
        next
      end
      t = self.task(key, hook, script, client_string)
      client_string = t.value
      t.join.kill
      return nil if client_string.nil?
    end
    return client_string
  end

  def task(key, hook, script, client_string)
    Thread.new {
      begin
        original_string = client_string.dup
        Thread.current[:script]  = script
        Thread.current[:session] = self.session
        exec_time = Benchmark.realtime { client_string = hook.call(client_string.dup)}
        self.report_exec_time(key, exec_time)
      rescue Exception => e
        self.remove(key)
        self.session.to_client <<~ERROR
          --- urnon: UpstreamHook Error
            script=#{script.name}
              hook=#{key}
          location=#{hook.source_location}
            Error:
              #{e.message}
            Backtrace:
              #{e.backtrace.join("\n")}
        ERROR
        client_string = original_string
      end
      client_string
    }
  end

  def report_exec_time(key, exec_time)
    return if (exec_time * 1000) < 50 # milliseconds
    self.session.to_client "warning(upstreamhook::#{key}) took #{Format.time(exec_time)}"
  end

  def remove(name)
    self.hooks.delete(name)
  end

  def list
    self.hooks.keys.dup
  end
end
