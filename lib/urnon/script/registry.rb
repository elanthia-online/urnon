require 'urnon/util/sessionize'

class Script < Thread
  extend Sessionize.new receiver: :scripts

  class Registry
    attr_reader :running, :session

    include Enumerable

    def initialize(session)
      @session = session
      @running = []
    end

    def each(...)
      self.running
        .select {|t| t.is_a?(Script)}
        .each(...)
    end

    def hidden()
      self.select(&:hidden?)
    end

    def atomic()
      Script::GLOBAL_SCRIPT_LOCK.synchronize {yield}
    end

    def _current()
      return Thread.current[:script] if Thread.current[:script].is_a?(Script)
      # fastest lookup possible
      return Thread.current if Thread.current.is_a?(Script)
      # second fastest lookup possible
      return Thread.current.parent if Thread.current.parent.is_a?(Script)
      # prefer current thread
      script = running.find {|script| script.eql?(Thread.current) }
      # else check if was launched by a script
      script = running.find {|script| script.eql?(Thread.current.parent) } if script.nil?
    end

    def current()
      script = _current
      return nil if script.nil?
      sleep 0.1 while script.paused?
      return script unless block_given?
      yield script
    end

    def script_name(file_name)
      file_name.slice(SCRIPT_DIR.size+1..-(File.extname(file_name).size + 1))
    end

    def running?(name)
      @running.any? { |i| (i.name =~ /^#{name}$/i) }
    end

    def pause(name=nil)
      if name.nil?
        self.current.pause
        return self.current
      end

      if s = @running.reject(&:paused?).find { |i| i.name.downcase == name.downcase}
        s.pause
        return s
      end
    end

    def unpause(name)
      if s = @running.select(&:paused?).find { |i| i.name.downcase == name.downcase}
        s.unpause
        return s
      end
    end

    def kill(name)
      return name.halt if name.is_a?(Script)
      if s = @running.find { |i| i.name.downcase == name.downcase }
        s.halt
        sleep 0.1 while s.status.is_a?(String)
      end
    end

    def by_session(session)
      @running.select {|script| script.session == session}
    end

    def paused?(name)
      if s = @running.select(&:paused?).find { |i| i.name.downcase == name.downcase}
        return s.paused?
      end

      return nil
    end

    def glob()
      File.join(SCRIPT_DIR, "**", "*.{lic,rb}")
    end

    def match(script_name)
      script_name = script_name.downcase
      pattern = if script_name.include?(".")
      then Regexp.new(Regexp.escape(script_name) + "$")
      else Regexp.new("%s.*\.(lic|rb)$" % Regexp.escape(script_name))
      end
      Dir.glob(self.glob)
        .select {|file|
          File.file?(file) && file =~ pattern
        }
        .sort_by {|file|
            file.index("#{script_name}.lic") ||
            file.index("#{script_name}.rb") ||
            file.size
        }
    end

    def exist?(script_name)
      match(script_name).size.eql?(1)
    end

    # this is not the way, ruby standards say it should be `exist?`
    def exists?(script_name)
      exist?(script_name)
    end

    def new_downstream_xml(line)
      self.each {|script|
        script.downstream_buffer.push(line.chomp) if script.want_downstream_xml
      }
    end

    def new_downstream(line)
      self.each {|script|
        script.downstream_buffer.push(line.chomp) if script.want_downstream
        unless script.watchfor.empty?
          script.watchfor.each_pair { |trigger,action|
            if line =~ trigger
              new_thread = Thread.new {
                sleep 0.011 until self.current
                begin
                    action.call
                rescue => e
                    print_error(e)
                end
              }
              script.thread_group.add(new_thread)
            end
          }
        end
      }
    end

    def new_upstream(line)
      self.each {|script|
        script.upstream_buffer.push(line.chomp) if script.want_upstream
      }
    end

    def new_script_output(line)
      self.each {|script|
        script.downstream_buffer.push(line.chomp) if script.want_script_output
      }
    end

    def log(data)
      script = self.current
      begin
          Dir.mkdir("#{LICH_DIR}/logs") unless File.exists?("#{LICH_DIR}/logs")
          File.open("#{LICH_DIR}/logs/#{script.name}.log", 'a') { |f| f.puts data }
          true
      rescue => e
          print_error(e)
          false
      end
    end

    def at_exit(&block)
      self.current do |script|
          script.at_exit(&block)
      end
    end

    def clear_exit_procs
      if script = self.current
          script.clear_exit_procs
      else
          respond "--- urnon: error: self.clear_exit_procs: can't identify calling script"
          return false
      end
    end

    def exit!
      if script = self.current
          script.exit!
      else
          respond "--- urnon: error: self.exit!: can't identify calling script"
          return false
      end
    end

    def find(name)
      self.list.find {|script| script.name.include?(name)}
    end

    def start(*args)
      self.of(args)
    end

    def start_exec_script(argv, opts = {})
      ExecScript.start(argv, opts.merge({session: self.session}))
    end

    def run(*args)
      s = self.of(args)
      return s unless s.is_a?(Script)
      s.value
      return s
    end

    def runtime(session)
      session.sandbox
    end

    def of(args)
      opts = {}
      (name, scriptv, kwargs) = args
      opts.merge!(kwargs) if kwargs.is_a?(Hash)
      opts[:name] = name
      opts[:file] = self.match(opts[:name]).first
      opts[:args] = scriptv
      opts[:session] = self.session

      raise ArgumentError, "could not start Script(%s) without a Session" % opts[:name] if session.nil?

      opts.merge!(scriptv) if scriptv.is_a?(Hash)

      if opts[:file].nil?
        self.session.to_client "--- urnon: could not find script #{opts[:name]} not found in #{self.glob}"
        return :not_found
      end

      opts[:name] = self.script_name opts[:file]

      if self.running.find { |s| s.name.eql?(opts[:name]) } and not opts[:force]
        self.session.to_client "--- urnon: #{opts[:name]} is already running"
        return :already_running
      end

      ::Script.new(opts) { |script, runtime|
        runtime = self.runtime(script.session)
        runtime.local_variable_set :script, script
        runtime.instance_eval(script.contents, script.file_name)
      }
    end
  end
end
