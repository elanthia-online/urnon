class DownstreamHook
  @@downstream_hooks ||= Hash.new
  def DownstreamHook.add(name, action)
     unless action.class == Proc
        echo "DownstreamHook: not a Proc (#{action})"
        return false
     end
     @@downstream_hooks[name] = action
  end
  def DownstreamHook.run(server_string)
     for key in @@downstream_hooks.keys
        begin
           exec_time = Benchmark.realtime {
              server_string = @@downstream_hooks[key].call(server_string.dup)
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