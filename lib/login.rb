#!/usr/bin/env ruby

# First attempt at login for cabal
# prototype only

require_relative("./legacy-launch")

module Login
  entry_data_file = "#{DATA_DIR}/entry.dat"
  launch_data = nil

  if defined?(Gtk)
    if File.exists?(entry_data_file)
      entry_data = File.open(entry_data_file, 'r') { |file|
      begin
        Marshal.load(file.read.unpack('m').first).sort do |a, b|
          [a[:game_name], a[:user_id], a[:char_name]] <=> [b[:game_name], b[:user_id], b[:char_name]]
        end
      rescue
        Array.new
      end
      }
    else
      entry_data = Array.new
    end
    done = false

    Gtk.queue {

        #
        # quick game entry tab
        #

      if entry_data.empty?
        box = Gtk::Box.new(:horizontal)
        box.pack_start(Gtk::Label.new('You have no saved login info.'), :expand => true, :fill => true, :padding => 5)
        quick_game_entry_tab = Gtk::Box.new(:vertical)
        quick_game_entry_tab.border_width = 5
        quick_game_entry_tab.pack_start(box, :expand => true, :fill => true, :padding => 0)
      else
        quick_box = Gtk::Box.new(:vertical)
        last_user_id = nil
        last_game_name = nil
        entry_data.each { |login_info|
          if login_info[:game_name] != last_game_name
            horizontal_separator = Gtk::Separator.new(:horizontal)
            quick_box.pack_start(horizontal_separator, :expand => false, :fill => false, :padding => 3)
            instance_label = Gtk::Label.new('<span foreground="cadetblue" size="large"><b>' + login_info[:game_name] + '</b></span>')
            instance_label.use_markup = true
            quick_box.pack_start(instance_label, :expand => false, :fill => false, :padding => 3)
            horizontal_separator = Gtk::Separator.new(:horizontal)
            quick_box.pack_start(horizontal_separator, :expand => false, :fill => false, :padding => 3)
          end
          if login_info[:user_id].downcase != last_user_id
            horizontal_separator = Gtk::Separator.new(:horizontal)
            quick_box.pack_start(horizontal_separator, :expand => false, :fill => false, :padding => 3)
          end
          last_user_id = login_info[:user_id].downcase
          account_label = Gtk::Label.new(last_user_id.upcase)
          account_label.set_size_request(75, 0)
          account_label.set_alignment(0, 0.5)
          last_game_name = login_info[:game_name]
          button_provider = Gtk::CssProvider.new
          button_provider.load(data: "button { font-size: 14px; color: navy; padding-top: 0px; padding-bottom: 0px; margin-top: 0px; margin-bottom: 0px; background-image: none; }\
                                         button:hover { background-color: darkgrey; } ")

          play_button = Gtk::Button.new()
          char_label = Gtk::Label.new("#{login_info[:char_name]}")
          fe_label = Gtk::Label.new("(#{login_info[:frontend].capitalize})")
          char_label.set_alignment(0, 0.5)
          fe_label.set_alignment(0.1, 0.5)
          button_row = Gtk::Paned.new(:horizontal)
          button_row.add1(char_label)
          button_row.add2(fe_label)
          button_row.set_position(110)

          play_button.add(button_row)
          play_button.set_alignment(0.0, 0.5)
          remove_button = Gtk::Button.new()
          remove_label = Gtk::Label.new('<span foreground="red"><b>Remove</b></span>')
          remove_label.use_markup = true
          remove_button.add(remove_label)
          remove_button.style_context.add_provider(button_provider, Gtk::StyleProvider::PRIORITY_USER)
          play_button.style_context.add_provider(button_provider, Gtk::StyleProvider::PRIORITY_USER)
          char_row = Gtk::Paned.new(:horizontal)
          char_row.add1(account_label)
          char_row.add2(play_button)

          char_box = Gtk::Box.new(:horizontal)
          char_box.pack_end(remove_button, :expand => false, :fill => false, :padding => 0)
          char_box.pack_start(char_row, :expand => true, :fill => true, :padding => 0)
          quick_box.pack_start(char_box, :expand => false, :fill => false, :padding => 0)

          remove_button.signal_connect('button-release-event') { |owner, ev|
            if (ev.event_type == Gdk::EventType::BUTTON_RELEASE) and (ev.button == 1)
              if (ev.state.inspect =~ /shift-mask/)
                entry_data.delete(login_info)
                save_entry_data = true
                char_box.visible = false
              else
                dialog = Gtk::MessageDialog.new(:parent => nil, :flags => :modal, :type => :question, :buttons => :yes_no, :message => "Delete record?")
                dialog.title = "Confirm"
                dialog.set_icon(@default_icon)
                response = nil
                response = dialog.run
                dialog.destroy
                if response == Gtk::ResponseType::YES
                  entry_data.delete(login_info)
                  save_entry_data = true
                  char_box.visible = false
                end
              end
            end
          }

          play_button.signal_connect('clicked') {
            play_button.sensitive = false
            launch_info = EAccess.auth(
              account: login_info[:user_id],
              password: login_info[:password],
              character: login_info[:char_name],
              game_code: login_info[:game_code]
            )

            LegacyLaunch.launch(
              launch_info: launch_info,
              front_end: login_info[:frontend]
            )
            done = true
            @window.destroy
          }
        }

        adjustment = Gtk::Adjustment.new(0, 0, 1000, 5, 20, 500)
        quick_vp = Gtk::Viewport.new(adjustment, adjustment)
        quick_vp.add(quick_box)
        quick_sw = Gtk::ScrolledWindow.new
        quick_sw.set_policy(:automatic, :automatic)
        quick_sw.add(quick_vp)
        quick_game_entry_tab = Gtk::Box.new(:vertical)
        quick_game_entry_tab.border_width = 5
        quick_game_entry_tab.pack_start(quick_sw, :expand => true, :fill => true, :padding => 5)
      end

      #
      # game entry tab
      #

      game_code, game_name = ''
      user_id_entry = Gtk::Entry.new
      pass_entry = Gtk::Entry.new
      pass_entry.visibility = false
      pass_entry.sensitive = true

      login_table = Gtk::Table.new(2, 2, false)
      login_table.attach(Gtk::Label.new('User ID:'), 0, 1, 0, 1, Gtk::AttachOptions::EXPAND | Gtk::AttachOptions::FILL, Gtk::AttachOptions::EXPAND | Gtk::AttachOptions::FILL, 5, 5)
      login_table.attach(user_id_entry, 1, 2, 0, 1, Gtk::AttachOptions::EXPAND | Gtk::AttachOptions::FILL, Gtk::AttachOptions::EXPAND | Gtk::AttachOptions::FILL, 5, 5)
      login_table.attach(Gtk::Label.new('Password:'), 0, 1, 1, 2, Gtk::AttachOptions::EXPAND | Gtk::AttachOptions::FILL, Gtk::AttachOptions::EXPAND | Gtk::AttachOptions::FILL, 5, 5)
      login_table.attach(pass_entry, 1, 2, 1, 2, Gtk::AttachOptions::EXPAND | Gtk::AttachOptions::FILL, Gtk::AttachOptions::EXPAND | Gtk::AttachOptions::FILL, 5, 5)

      disconnect_button = Gtk::Button.new(:label => ' Disconnect ')
      disconnect_button.sensitive = false

      connect_button = Gtk::Button.new(:label => ' Connect ')
      connect_button.sensitive = true

      login_button_box = Gtk::Box.new(:horizontal)
      login_button_box.pack_end(connect_button, :expand => false, :fill => false, :padding => 5)
      login_button_box.pack_end(disconnect_button, :expand => false, :fill => false, :padding => 5)

      liststore = Gtk::ListStore.new(String, String, String, String)
      liststore.set_sort_column_id(1, :ascending)

      renderer = Gtk::CellRendererText.new

      treeview = Gtk::TreeView.new(liststore)
      treeview.height_request = 160

      col = Gtk::TreeViewColumn.new("Game", renderer, :text => 1)
      col.resizable = true
      treeview.append_column(col)

      col = Gtk::TreeViewColumn.new("Character", renderer, :text => 3)
      col.resizable = true
      treeview.append_column(col)

      sw = Gtk::ScrolledWindow.new
      sw.set_policy(:automatic, :automatic)
      sw.add(treeview)

      front_end = Gtk::Label.new("Frontend:")
      illthorn_option = Gtk::RadioButton.new(:label => 'Illthorn')
      wizard_option = Gtk::RadioButton.new(:label => 'Wizard', :member => illthorn_option)
      stormfront_option = Gtk::RadioButton.new(:label => 'Stormfront', :member => illthorn_option)
      avalon_option = Gtk::RadioButton.new(:label => 'Avalon', :member => illthorn_option)
      suks_option = Gtk::RadioButton.new(:label => 'suks', :member => illthorn_option)

      frontend_box = Gtk::Box.new(:horizontal, 10)

      frontend_box.pack_start(front_end)
      frontend_box.pack_start(illthorn_option, :expand => false, :fill => false, :padding => 0)
      frontend_box.pack_start(wizard_option, :expand => false, :fill => false, :padding => 0)
      frontend_box.pack_start(stormfront_option, :expand => false, :fill => false, :padding => 0)

      if RUBY_PLATFORM =~ /darwin/i
        frontend_box.pack_start(avalon_option, :expand => false, :fill => false, :padding => 0)
      end

      custom_launch_option = Gtk::CheckButton.new('Custom launch command')
      custom_launch_entry = Gtk::ComboBoxEntry.new()
      custom_launch_entry.child.text = "(enter custom launch command)"
      custom_launch_entry.append_text("Wizard.Exe /GGS /H127.0.0.1 /P%port% /K%key%")
      custom_launch_entry.append_text("Stormfront.exe /GGS/Hlocalhost/P%port%/K%key%")
      custom_launch_dir = Gtk::ComboBoxEntry.new()
      custom_launch_dir.child.text = "(enter working directory for command)"
      custom_launch_dir.append_text("../wizard")
      custom_launch_dir.append_text("../StormFront")

      make_quick_option = Gtk::CheckButton.new('Save this info for quick game entry')

      play_button = Gtk::Button.new(:label => ' Play ')
      play_button.sensitive = false

      play_button_box = Gtk::Box.new(:horizontal)
      play_button_box.pack_end(play_button, :expand => false, :fill => false, :padding => 5)

      game_entry_tab = Gtk::Box.new(:vertical)
      game_entry_tab.border_width = 5
      game_entry_tab.pack_start(login_table, :expand => false, :fill => false, :padding => 0)
      game_entry_tab.pack_start(login_button_box, :expand => false, :fill => false, :padding => 0)
      game_entry_tab.pack_start(sw, :expand => true, :fill => true, :padding => 3)
      game_entry_tab.pack_start(frontend_box, :expand => false, :fill => false, :padding => 3)
      game_entry_tab.pack_start(custom_launch_option, :expand => false, :fill => false, :padding => 3)
      game_entry_tab.pack_start(custom_launch_entry, :expand => false, :fill => false, :padding => 3)
      game_entry_tab.pack_start(custom_launch_dir, :expand => false, :fill => false, :padding => 3)
      game_entry_tab.pack_start(make_quick_option, :expand => false, :fill => false, :padding => 3)
      game_entry_tab.pack_start(play_button_box, :expand => false, :fill => false, :padding => 3)

      custom_launch_option.sensitive = false
      custom_launch_option.active = false

      custom_launch_option.signal_connect('toggled') {
        custom_launch_entry.visible = custom_launch_option.active?
        custom_launch_dir.visible = custom_launch_option.active?
      }

      avalon_option.signal_connect('toggled') {
        if avalon_option.active?
          custom_launch_option.active = false
          custom_launch_option.sensitive = false
        else
          custom_launch_option.sensitive = true
        end
      }

      illthorn_option.signal_connect('toggled') {
        if illthorn_option.active?
          custom_launch_option.active = false
          custom_launch_option.sensitive = false
        else
          custom_launch_option.sensitive = true
        end
      }



      connect_button.signal_connect('clicked') {
        connect_button.sensitive = false
        user_id_entry.sensitive = false
        pass_entry.sensitive = false
        iter = liststore.append
        iter[1] = 'working...'
        Gtk.queue {
          begin
            login_info = EAccess.auth(
              account: user_id_entry.text || argv.account,
              password: pass_entry.text || argv.password,
              legacy: true
            )
          end
          liststore.clear
          login_info.each do |row|
            iter = liststore.append
            iter[0] = row[:game_code]
            iter[1] = row[:game_name]
            iter[2] = row[:char_code]
            iter[3] = row[:char_name]
          end
          disconnect_button.sensitive = true
        }
      }

      treeview.signal_connect('cursor-changed') {
        play_button.sensitive = true
      }

      disconnect_button.signal_connect('clicked') {
        disconnect_button.sensitive = false
        play_button.sensitive = false
        liststore.clear
        connect_button.sensitive = true
        user_id_entry.sensitive = true
        pass_entry.sensitive = true
      }

      play_button.signal_connect('clicked') {

        play_button.sensitive = false
        game_code = treeview.selection.selected[0]
        char_code = treeview.selection.selected[2]
        char_name = treeview.selection.selected[3]
        launch_info = EAccess.auth(
          game_code: game_code,
          character: char_name,
          account: user_id_entry.text,
          password: pass_entry.text
        )
          # Insert call to FE launch module
        if avalon_option.active?
          fe_chosen = 'avalon'
        elsif illthorn_option.active?
          fe_chosen = 'illthorn'
        else
          nil
        end
        LegacyLaunch.launch(
          launch_info: launch_info,
          front_end: fe_chosen
        )

        done = true
        @window.destroy
      }

        #
        # put it together and show the window
        #
      silver = Gdk::RGBA::parse("#d3d3d3")
      notebook = Gtk::Notebook.new
      notebook.override_background_color(:normal, silver)
      notebook.append_page(quick_game_entry_tab, Gtk::Label.new('Quick Game Entry'))
      notebook.append_page(game_entry_tab, Gtk::Label.new('Game Entry'))
      notebook.signal_connect('switch-page') { |who, page, page_num| }
      grey = Gdk::RGBA::parse("#d3d3d3")
      @window = Gtk::Window.new
      @window.title = "Cabal v#{CABAL_VERSION}"
      @window.border_width = 5
      @window.add(notebook)
      @window.signal_connect('delete_event') { @window.destroy; exit! }
      @window.default_width = 400
      @window.default_height = 700
      @window.window_position = Gtk::WindowPosition::NONE
      @window.show_all

      custom_launch_entry.visible = custom_launch_option.active?
      custom_launch_dir.visible = custom_launch_option.active?

  #    wait_until { done }
      #
      # processing for saving to quick entry
      #

    }
  end
end
