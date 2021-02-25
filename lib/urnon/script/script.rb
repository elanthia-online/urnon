require "benchmark"
require 'urnon/session'
require "urnon/util/limited-array"
require "urnon/util/format"
require "urnon/ext/thread"
require 'urnon/script/runtime'
require 'urnon/script/opts'
require 'urnon/util/escape'

class Script < Thread
  class Shutdown < StandardError; end;
  # internal script status codes
  class Status
    Err    = :err
    Ok     = :ok
    Killed = :killed
  end
  # global scripting lock
  GLOBAL_SCRIPT_LOCK ||= Mutex.new

  Script.abort_on_exception  = false
  Script.report_on_exception = false

  attr_reader :name, :vars, :safe,
              :file_name, :at_exit_procs,
              :thread_group, :_value, :shutdown,
              :start_time, :run_time,
              :session

  attr_accessor :quiet, :no_echo, :paused,
                :hidden, :silent,
                :want_downstream, :want_downstream_xml,
                :want_upstream, :want_script_output,
                :no_pause_all, :no_kill_all,
                :downstream_buffer, :upstream_buffer, :unique_buffer,
                :die_with, :watchfor, :command_line, :ignore_pause,
                :_value, :exit_status, :opts

  def initialize(args, &block)
    @file_name = args[:file]
    @name = args[:name]
    @session = args[:session]
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
    @opts  = Opts.parse(@vars)
    @quiet = args.fetch(:quiet, false)
    @downstream_buffer = LimitedArray.new
    @want_downstream = true
    @want_downstream_xml = false
    @want_script_output = false
    @upstream_buffer = LimitedArray.new
    @want_upstream = false
    @unique_buffer = LimitedArray.new
    @watchfor = Hash.new
    @_value = :unknown
    @at_exit_procs = []
    @die_with = []
    @hidden = false
    @no_pause_all = false
    @no_kill_all = false
    @silent = false
    @shutdown = false
    @paused = false
    @no_echo = false
    @thread_group = ThreadGroup.new
    @start_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    @exit_status = nil
    @session.scripts.running.push(self)
    @thread_group.add(self)
    super {
      self.priority = 1
      Thread.handle_interrupt(Script::Shutdown => :never) do
        script = self
        begin
          Thread.handle_interrupt(Script::Shutdown => :immediate) do
            respond("--- urnon: #{script.name} active.") unless script.quiet
            begin
              script._value = yield(script, self)
            rescue Shutdown => e
              script.exit_status = Status::Killed
            rescue Exception => e
              script.print_error(e)
              script.exit_status = Status::Err
            else
              script.exit_status = Status::Ok if script.exit_status.nil?
            end
          end
        ensure
          script.exit_status = Status::Killed unless script.exit_status
          script._value = nil if script._value.eql?(:unknown)
          script.before_shutdown()
          respond("--- urnon: #{script.name} exiting with status: #{script.exit_status} in #{script.uptime}")
          script.halt()
        end
      end
    }
  end

  def print_error(e)
    self.session.to_client Urnon::Escape.to_front_end("script:%s:error: %s\n%s" % [
      self.name,
      e.message,
      e.backtrace.join("\n")
    ])
  end

  def uptime()
    Format.time(Process.clock_gettime(Process::CLOCK_MONOTONIC) - start_time)
  end

  def before_shutdown()
    begin
      @shutdown = true
      at_exit_procs.each(&:call)
      # ensure sub-scripts are kills
      @die_with.each { |script_name| Script.unsafe_kill(script_name) }
      # all Thread created by this script
      resources = @thread_group.list + self.child_threads
      resources.each {|child|
        unless child.is_a?(Script)
          child.dispose
          Thread.kill(child)
        end
      }
    rescue StandardError => e
      print_error(e)
    end
    self
  end

  def value()
    return @_value unless @_value.eql?(:unknown)
    super
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
    "%s<%s status=%s uptime=%s value=%s>" % [
      self.name, @name,
        self.status, uptime, @_value.inspect]
  end

  def status()
    return super if alive?
    return @exit_status
  end

  def script()
    # todo: deprecate this
    self
  end

  def halt()
    return if @_halting
    @_halting = true
    begin
      @exit_status = Status::Killed unless @exit_status
      if self.alive?
        self.raise(Script::Shutdown)
        self.join(10) rescue nil
        @_value = :shutdown if @_value.eql?(:unknown)
      end
    ensure
      self.session.scripts.running.delete(self)
      self.dispose()
      self.kill()
      self
    end
  end

  def at_exit(&block)
    return @at_exit_procs << block if block_given?
    respond '--- warning: Script.at_exit called with no code block'
  end

  def clear_exit_procs
    @at_exit_procs.clear
    true
  end

  def exit(status = 0)
    @exit_status = status
    self.halt
  end

  def exit!
    @at_exit_procs.clear
    self.exit(:sigkill)
  end

  def has_thread?(t)
    @thread_group.list.include?(t)
  end

  def pause
    respond "--- urnon: #{@name} paused."
    @paused = true
  end

  def unpause
    respond "--- urnon: #{@name} unpaused."
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

  def feedme_upstream
    @want_upstream = !@want_upstream
  end
end
