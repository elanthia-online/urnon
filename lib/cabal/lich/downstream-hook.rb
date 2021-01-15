class DownstreamHook
  @@downstream_hooks ||= Hash.new
  def DownstreamHook.add(name, action, session = Script.current.session)
     unless action.is_a?(Proc)
        echo <<~ERR
          DownstreamHook: #{action.class.name} is not a Proc
          0. #{name.inspect}
          1. #{action.inspect}
          backtrace:
          #{Thread.current.backtrace.join("\n")}
        ERR
        return false
     end
     @@downstream_hooks[name] = [action, session]
  end
  def DownstreamHook.run(server_string)
     for key in @@downstream_hooks.keys
      begin
        hook, session = @@downstream_hooks[key]
        exec_time = Benchmark.realtime {
          case hook.arity
          when 1
            server_string = hook.call(server_string.dup)
          when 2
            server_string = hook.call(server_string.dup, session)
          end
        }
        if (exec_time * 1_000 > 50)
          respond "warning(downstreamhook::#{key}) took #{exec_time * 1_000}"
        end
      rescue
        @@downstream_hooks.delete(key)
        respond "--- Lich: DownstreamHook: #{$!}"
        respond $!.backtrace.first
      end
        return nil if server_string.nil?
     end
     return server_string
  end
  def DownstreamHook.remove(name)
     @@downstream_hooks.delete(name)
  end
  def DownstreamHook.list
     @@downstream_hooks.keys.dup
  end
end
