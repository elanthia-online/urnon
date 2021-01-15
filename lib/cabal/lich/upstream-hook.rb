
class UpstreamHook
  @@upstream_hooks ||= Hash.new
  def UpstreamHook.add(name, action, session = Script.current.session)
     unless action.class == Proc
        echo "UpstreamHook: not a Proc (#{action})"
        return false
     end
     @@upstream_hooks[name] = [action, session]
  end
  def UpstreamHook.run(client_string)
     for key in @@upstream_hooks.keys
      begin
        (hook, session) = @@upstream_hooks[key]
        case hook.arity
        when 1
          client_string = hook.call(client_string)
        when 2
          client_string = hook.call(client_string, session)
        end
      rescue
        @@upstream_hooks.delete(key)
        respond "--- Lich: UpstreamHook: #{$!}"
        respond $!.backtrace.first
      end
      return nil if client_string.nil?
     end
     return client_string
  end
  def UpstreamHook.remove(name)
     @@upstream_hooks.delete(name)
  end
  def UpstreamHook.list
     @@upstream_hooks.keys.dup
  end
end
