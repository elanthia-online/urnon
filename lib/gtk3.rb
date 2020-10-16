require 'gtk3'
HAVE_GTK=true
if defined?(Gtk)
  pp "Initialized GTK"
  Gdk.module_eval do
    define_deprecated_singleton_method :screen_height, :warn => "Gdk::screen_height is deprecated; use monitor methods instead" do |_self|
      99999
    end

    define_deprecated_singleton_method :screen_width, :warn => "Gdk::screen_width is deprecated; use monitor methods instead" do |_self|
      99999
    end
  end

  Gtk::Drag.module_eval do
    define_deprecated_const :TARGET_SAME_APP, "Gtk::TargetFlags::SAME_APP"
    define_deprecated_const :DEST_DEFAULT_ALL, "Gtk::DestDefaults::ALL"
  end

  Gtk.module_eval do
    # Deprecation updates to keep gtk3 mostly going in gtk2
    define_deprecated_const(:ComboBoxEntry, nil)
    define_deprecated_const(:Tooltips, nil)

    Gtk::ComboBox.class_eval do
      def append_text(text)
        respond "'Gtk::ComboBox#append_text' is deprecated; use 'Gtk::ComboBoxText#append_text' instead"
      end
    end

    class Gtk::ComboBoxEntry < Gtk::ComboBoxText
      def initialize()
        respond "'Gtk::ComboBoxEntry' is deprecated; use 'Gtk::ComboBoxText(:entry => true)' instead"
        super(:entry => true)
      end
    end

    Gtk::Entry.class_eval do
      def set_text(text)
        if text.nil?
          respond "'Gtk::Entry#set_text' no longer accepts nil values; fix me"
          text = ""
        end
        parent.set_text(text)
        return self
      end
    end

    Gtk::HBox.class_eval do
      define_deprecated_singleton_method :new, :warn => "Use 'Gtk::Box.new(:horizontal, spacing)'." do |_self, homogeneous, spacing|
        respond "'Gtk::Hbox' is deprecated; use 'Gtk::Box.new(:horizontal, spacing)'."
        box = Gtk::Box.new(:horizontal, spacing)
        box.set_homogeneous(homogeneous ? true : false)
        box
      end
    end

    Gtk::Notebook.class_eval do
      def set_tab_border(border)
        respond "'Gtk::Notebook:set_tab_border()' is deprecated; fix me"
        # noop
        return self
      end
    end

    Gtk::ToggleButton.class_eval do
      def set_active(active)
        if active.nil?
          respond "'Gtk::ToggleButton#set_active' no longer accepts nil values; fix me"
          active = false
        end
        parent.set_active(active)
        return self
      end
    end

    class Gtk::Tooltips < Gtk::Tooltip
      def enable
        respond "'Gtk::Tooltips#enable' is deprecated; use 'Gtk::Tooltip' API instead"
        # noop
        return self
      end

      def set_tip(one = nil, two = nil, three = nil)
        respond "'Gtk::Tooltips#set_tip' is deprecated; use 'Gtk::Tooltip' API instead"
        # noop
        return self
      end
    end

    Gtk::VBox.class_eval do
      define_deprecated_singleton_method :new, :warn => "Use 'Gtk::Box.new(:vertical, spacing)'." do |_self, homogeneous, spacing|
        respond "'Gtk::VBox' is deprecated; use 'Gtk::Box.new(:vertical, spacing)' instead"
        box = Gtk::Box.new(:vertical, spacing)
        box.set_homogeneous(homogeneous ? true : false)
        box
      end
    end
      # Calling Gtk API in a thread other than the main thread may cause random segfaults
    def Gtk.queue(&block)
		 pp "Running GTK block"
         GLib::Timeout.add(1) {
            begin
              block.call
            rescue
               respond "error in Gtk.queue: #{$!}"
               puts "error in Gtk.queue: #{$!}\n\t#{$!.backtrace.join("\n\t")}"
               Lich.log "error in Gtk.queue: #{$!}\n\t#{$!.backtrace.join("\n\t")}"
            rescue SyntaxError
               respond "error in Gtk.queue: #{$!}"
			   puts "error in Gtk.queue: #{$!}\n\t#{$!.backtrace.join("\n\t")}"
               Lich.log "error in Gtk.queue: #{$!}\n\t#{$!.backtrace.join("\n\t")}"
            rescue SystemExit
			   puts "error in Gtk.queue: #{$!}\n\t#{$!.backtrace.join("\n\t")}"
               nil
            rescue SecurityError
               respond "error in Gtk.queue: #{$!}"
               puts "error in Gtk.queue: #{$!}\n\t#{$!.backtrace.join("\n\t")}"
               Lich.log "error in Gtk.queue: #{$!}\n\t#{$!.backtrace.join("\n\t")}"
            rescue ThreadError
               respond "error in Gtk.queue: #{$!}"
               puts "error in Gtk.queue: #{$!}\n\t#{$!.backtrace.join("\n\t")}"
               Lich.log "error in Gtk.queue: #{$!}\n\t#{$!.backtrace.join("\n\t")}"
            rescue SystemStackError
               respond "error in Gtk.queue: #{$!}"
               puts "error in Gtk.queue: #{$!}\n\t#{$!.backtrace.join("\n\t")}"
               Lich.log "error in Gtk.queue: #{$!}\n\t#{$!.backtrace.join("\n\t")}"
            rescue Exception
               respond "error in Gtk.queue: #{$!}"
               puts "error in Gtk.queue: #{$!}\n\t#{$!.backtrace.join("\n\t")}"
               Lich.log "error in Gtk.queue: #{$!}\n\t#{$!.backtrace.join("\n\t")}"
            rescue ScriptError
               respond "error in Gtk.queue: #{$!}"
               puts "error in Gtk.queue: #{$!}\n\t#{$!.backtrace.join("\n\t")}"
               Lich.log "error in Gtk.queue: #{$!}\n\t#{$!.backtrace.join("\n\t")}"
            rescue LoadError
               respond "error in Gtk.queue: #{$!}"
               puts "error in Gtk.queue: #{$!}\n\t#{$!.backtrace.join("\n\t")}"
               Lich.log "error in Gtk.queue: #{$!}\n\t#{$!.backtrace.join("\n\t")}"
            rescue NoMemoryError
               respond "error in Gtk.queue: #{$!}"
               puts "error in Gtk.queue: #{$!}\n\t#{$!.backtrace.join("\n\t")}"
               Lich.log "error in Gtk.queue: #{$!}\n\t#{$!.backtrace.join("\n\t")}"
            rescue
               respond "error in Gtk.queue: #{$!}"
               puts "error in Gtk.queue: #{$!}\n\t#{$!.backtrace.join("\n\t")}"
               Lich.log "error in Gtk.queue: #{$!}\n\t#{$!.backtrace.join("\n\t")}"
            end
            false # don't repeat timeout
         }
      end
   end

   def gtk3_sleep_while_idle()
      sleep 0.1
   end
   
  begin
      Gtk.queue {
	  pp "And again?"
         # Add a function to call for when GTK is idle
         Gtk.idle_add do
            gtk3_sleep_while_idle
         end
      }
  rescue
    nil # fixme
  end
end

