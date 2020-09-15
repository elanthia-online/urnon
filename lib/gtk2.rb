require "gtk2"
HAVE_GTK=true
module Gtk
  Gdk::Threads.init
  
  def Gtk.queue()
    Gdk::Threads.synchronize {yield}
  end
end