require "benchmark"

SCRIPT_CONTEXT = binding()

class Script < Thread
  GLOBAL_SCRIPT_LOCK ||= Mutex.new
  @@running          ||= Array.new
  @@lock_holder      ||= nil

  Script.abort_on_exception  = false
  Script.report_on_exception = false

  def self.running(); @@running.dup; end
  def self.list(); Script.running(); end
  def self.hidden(); running.select(&:hidden?); end
  def self.atomic(); GLOBAL_SCRIPT_LOCK.synchronize {yield}; end

  def self.namescript_incoming(line)
     Script.new_downstream(line)
  end

  def self.current()
    # prefer current thread
    script = running.find {|script| script.eql?(Thread.current) }
    # else check if was launched by a script
    script = running.find {|script| script.eql?(Thread.current.parent) } if script.nil?
    return nil if script.nil?
    sleep 0.1 while script.paused?
    return script unless block_given?
    yield script
  end

  def self.self(); current(); end

  def self.start(*args)
     Script.of(args)
  end
  
  def self.run(*args)
     s = Script.of(args)
     s.value
     return s
  end

  def self.script_name(file_name)
     file_name.slice(SCRIPT_DIR.size+1..-(File.extname(file_name).size + 1))
  end

  def self.running?(name)
     @@running.any? { |i| (i.name =~ /^#{name}$/i) }
  end

  def self.pause(name=nil)
    if name.nil?
      Script.current.pause
      return Script.current
    end

    if s = @@running.reject(&:paused?).find { |i| i.name.downcase == name.downcase}
      s.pause
      return s
    end
  end

  def self.unpause(name)
     if s = @@running.select(&:paused?).find { |i| i.name.downcase == name.downcase}
        s.unpause
        return s
     end
  end

  def self.kill(name)
    if s = @@running.find { |i| i.name.downcase == name.downcase}
      return s if s.nil?
      # this handles the case where a script says `before_dying {Script.kill(<script>)}`
      # to prevent a recursive dead-lock
      return s.kill_tree() if @@lock_holder.nil?
      return s.kill()      if @@lock_holder.eql?(s.parent)
    end
  end

  def self.paused?(name)
    if s = @@running.select(&:paused?).find { |i| i.name.downcase == name.downcase}
      return s.paused?
    end

    return nil
  end

  def self.glob()
     File.join(SCRIPT_DIR, "**", "*.{lic,rb}")
  end

  def self.match(script_name)
     script_name = script_name.downcase
     Dir.glob(Script.glob)
        .select {|file| file.downcase.slice(SCRIPT_DIR.size..-1).include?(script_name) }
        .sort_by {|file|
           file.index("#{script_name}.lic") || file.index("#{script_name}.rb") || file.size
        }
  end

  def self.exists?(script_name)
     match(script_name).any? {|path| File.file?(path) }
  end

  def self.new_downstream_xml(line)
     for script in @@running
        script.downstream_buffer.push(line.chomp) if script.want_downstream_xml
     end
  end

  def self.new_upstream(line)
     for script in @@running
        script.upstream_buffer.push(line.chomp) if script.want_upstream
     end
  end

  def self.new_downstream(line)
     @@running.each { |script|
        script.downstream_buffer.push(line.chomp) if script.want_downstream
        unless script.watchfor.empty?
           script.watchfor.each_pair { |trigger,action|
              if line =~ trigger
                 new_thread = Thread.new {
                    sleep 0.011 until Script.current
                    begin
                       action.call
                    rescue
                       echo "watchfor error: #{$!}"
                    end
                 }
                 script.thread_group.add(new_thread)
              end
           }
        end
     }
  end

  def self.new_script_output(line)
     for script in @@running
        script.downstream_buffer.push(line.chomp) if script.want_script_output
     end
  end

  def self.log(data)
     script = Script.current
     begin
        Dir.mkdir("#{LICH_DIR}/logs") unless File.exists?("#{LICH_DIR}/logs")
        File.open("#{LICH_DIR}/logs/#{script.name}.log", 'a') { |f| f.puts data }
        true
     rescue
        respond "--- lich: error: Script.log: #{$!}"
        false
     end
  end

  def self.open_file(*args)
   fail Exception, "Script.open_file() is hard deprecated use the normal File class"
  end

  def self.at_exit(&block)
     Script.current do |script|
        script.at_exit(&block)
     end
  end

  def self.clear_exit_procs
     if script = Script.current
        script.clear_exit_procs
     else
        respond "--- lich: error: Script.clear_exit_procs: can't identify calling script"
        return false
     end
  end

  def self.exit!
     if script = Script.current
        script.exit!
     else
        respond "--- lich: error: Script.exit!: can't identify calling script"
        return false
     end
  end

  def self.find(name)
    Script.list.find {|script| script.name.include?(name)}
  end

  def self.of(args)
    opts = {}
    (name, scriptv, kwargs) = args
    opts.merge!(kwargs) if kwargs.is_a?(Hash)
    opts[:name] = name
    opts[:file] = Script.match(opts[:name]).first
    opts[:args] = scriptv

    opts.merge!(scriptv) if scriptv.is_a?(Hash)
    
    if opts[:file].nil?
      return respond "--- lich: could not find script #{opts[:name]} not found in #{Script.glob}"
    end

    opts[:name] = Script.script_name opts[:file]

    #Log.out(opts, label: %i(script of))

    if Script.running.find { |s| s.name.eql?(opts[:name]) } and not opts[:force]
      return respond "--- lich: #{opts[:name]} is already running" 
    end

    Script.new(opts) { |script|
      runtime = SCRIPT_CONTEXT.dup
      runtime.local_variable_set :script, script
      runtime.local_variable_set :context, runtime
      runtime.eval(script.contents, script.file_name)
    }
  end

  attr_reader :name, :vars, :safe, 
              :file_name, :at_exit_procs,
              :thread_group

  attr_accessor :quiet, :no_echo, :paused,
                :hidden, :silent,
                :want_downstream, :want_downstream_xml, 
                :want_upstream, :want_script_output, 
                :no_pause_all, :no_kill_all, 
                :downstream_buffer, :upstream_buffer, :unique_buffer, 
                :die_with, :watchfor, :command_line, :ignore_pause,
                :exit_status, :start_time, :run_time

  def initialize(args, &block)
   @file_name = args[:file]
   @name = args[:name]
   @vars = case args[:args]
      when Array 
         args[:args]
      when String
         if args[:args].empty?
            []
         else
            [args[:args]].concat(args[:args]
               .scan(/[^\s"]*(?<!\\)"(?:\\"|[^"])+(?<!\\)"[^\s]*|(?:\\"|[^"\s])+/)
               .collect { |s| s.gsub(/(?<!\\)"/,'')
               .gsub('\\"', '"') })
         end
      else
         []
      end
   @quiet = args.fetch(:quiet, false)
   @downstream_buffer = LimitedArray.new
   @want_downstream = true
   @want_downstream_xml = false
   @want_script_output = false
   @upstream_buffer = LimitedArray.new
   @want_upstream = false
   @unique_buffer = LimitedArray.new
   @watchfor = Hash.new
   @at_exit_procs = Array.new
   @die_with = Array.new
   @hidden = false
   @no_pause_all = false
   @no_kill_all = false
   @silent = false
   @safe = false
   @paused = false
   @no_echo = false
   @thread_group = ThreadGroup.new
   @start_time = Time.now.to_i
   @run_time = 0
   @exit_status = 0
   @@running.push(self)
   @thread_group.add(self)
   super {
     self[:name] = @name
     self.priority = 1
     self.run_time = Benchmark.realtime {
        begin
          respond("--- lich: #{self.name} active.") unless self.quiet
          @value = yield(self)
          self.exit_status = 0
        rescue Exception => e
          respond e
          respond e.backtrace
          self.exit_status = 1
        ensure
         # ensure before_dying is ran
         script.before_shutdown()
         # ensure sub-threads are killed
         (@thread_group.list + self.child_threads)
          .each {|child| child.kill unless child.is_a?(Script) }
        end
     }
     script.kill()
   }
  end

  def before_shutdown()
    @at_exit_procs.each { |cb|
      begin
        cb.call()
      rescue => exception
        respond(exception.message)
      end
    }
    @at_exit_procs.clear
    # ensure sub-scripts are kills
    @die_with.each { |script_name| Script.unsafe_kill(script_name) }
    @die_with.clear
    @@running.delete(self)
  end

  def value()
    super || @value
  end

  def script
    self
  end

  def child_threads()
    Thread.list.select {|thread| thread.parent.eql? self }
  end

  def db()
    SQLite3::Database.new("#{DATA_DIR}/#{script.name.gsub(/\/|\\/, '_')}.db3")
  end

  def contents()
    File.read(self.file_name)
  end

  def hidden?
     @hidden
  end

  def inspect
    "%s<%s>" % [self.class.name, @name]
  end

  def status()
    return super if alive?
    return exit_status
  end

  def kill()
    begin
      return unless @@running.include?(self)
      super
      respond("--- lich: #{self.name} exiting with status: #{self.exit_status} in #{Format.time(self.run_time)}")
      self.dispose()
      GC.start
    rescue
      respond "--- lich: error: #{$!}\n\t#{$!.backtrace.join("\n\t")}"
      Lich.log "error: #{$!}\n\t#{$!.backtrace.join("\n\t")}"
    end
  end

  def kill_tree()
    #Log.out({this: self.name, parent: self.parent.name}, label: %i(script kill))
    GLOBAL_SCRIPT_LOCK.synchronize { 
      @@lock_holder = self 
      self.kill()
      @@lock_holder = nil
    }
    self
  end

  def at_exit(&block)
     if block
        @at_exit_procs.push(block)
        return true
     else
        respond '--- warning: Script.at_exit called with no code block'
        return false
     end
  end

  def clear_exit_procs
     @at_exit_procs.clear
     true
  end
  
  def exit(status = 0)
    @exit_status = status
    kill
  end

  def exit!
    @at_exit_procs.clear
    exit(1)
  end

  def has_thread?(t)
     @thread_group.list.include?(t)
  end

  def pause
     respond "--- lich: #{@name} paused."
     @paused = true
  end

  def unpause
     respond "--- lich: #{@name} unpaused."
     @paused = false
  end

  def paused?
   @paused == true
  end

  def clear
     to_return = @downstream_buffer.dup
     @downstream_buffer.clear
     to_return
  end

  def gets
     # fixme: no xml gets
     if @want_downstream or @want_downstream_xml or @want_script_output
        sleep 0.05 while @downstream_buffer.empty?
        @downstream_buffer.shift
     else
        echo 'this script is set as unique but is waiting for game data...'
        sleep 2
        false
     end
  end

  def gets?
     if @want_downstream or @want_downstream_xml or @want_script_output
        if @downstream_buffer.empty?
           nil
        else
           @downstream_buffer.shift
        end
     else
        echo 'this script is set as unique but is waiting for game data...'
        sleep 2
        false
     end
  end

  def upstream_gets
     sleep 0.05 while @upstream_buffer.empty?
     @upstream_buffer.shift
  end

  def upstream_gets?
     if @upstream_buffer.empty?
        nil
     else
        @upstream_buffer.shift
     end
  end
 
  def unique_gets
     sleep 0.05 while @unique_buffer.empty?
     @unique_buffer.shift
  end

  def unique_gets?
     if @unique_buffer.empty?
        nil
     else
        @unique_buffer.shift
     end
  end

  def safe?
     @safe
  end
  
  def feedme_upstream
     @want_upstream = !@want_upstream
  end
end