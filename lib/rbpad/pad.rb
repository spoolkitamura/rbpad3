
require 'gtk3'
require 'tempfile'

begin
  require 'win32ole'
rescue LoadError => e
end

require 'rbpad/output'
require 'rbpad/input'
require 'rbpad/editor'
require 'rbpad/config'
require 'rbpad/util'
require 'rbpad/error_jp'
require 'rbpad/version'


module Rbpad

  class Pad < Gtk::Window
    DEFAULT_W = 800
    DEFAULT_H = 650
    def initialize(lang = :jp, w = DEFAULT_W, h = DEFAULT_H)
      super("rbpad (#{VERSION})")
      if w <= 0 and h <= 0
        self.set_size_request(DEFAULT_W, DEFAULT_H)
        self.maximize
      else
        self.set_size_request(w, h)
      end

      @lang       = lang                             # language(:jp/:en)
      @drb_portno = 49323                            # port number for DRb
      @q          = Queue.new                        # queue for Inter-thread communication
      @last_dir   = nil                              # directory of last opened or saved

      @conf = Config.new(
                binding,   # to create Proc instance in `class Pad` context
                Utility.get_os,
                @lang
              )

      # menu
      @uimanager  = Gtk::UIManager.new               # UIManager
      _set_menu                                      # set menu
      self.add_accel_group(@uimanager.accel_group)   # enable to use shortcut keys

      # console for output
      @console_output = ConsoleOutput.new(@conf)
      frame_output = Gtk::Frame.new(@conf.messages[:frame_output])
      frame_output.add(@console_output)

      # console for input
      @console_input = ConsoleInput.new(@conf, @drb_portno)
      frame_input = Gtk::Frame.new(@conf.messages[:frame_input])
      frame_input.add(@console_input)

      # statu area
      status_area = Gtk::Label.new
      status_area.set_alignment(0, 0.5)
      status_area.override_font(Pango::FontDescription.new("#{@conf.platform[:font][:status]}"))
      frame_status = Gtk::Frame.new
      frame_status.add(status_area)

      # editor
      @editor = Editor.new(@conf, status_area)
      @editor.set_draw_spaces(@uimanager.get_widget("/MenuBar/option/drawspaces").active?)
      @editor.set_block_match(@uimanager.get_widget("/MenuBar/option/blockmatch").active?)

      # vertical pane for edtor and output console
      vpaned = Gtk::Paned.new(:vertical)
      vpaned.pack1(@editor, resize: true, shrink: false)
      vpaned.pack2(frame_output.set_shadow_type(:etched_in), resize: true, shrink: false)
      vpaned.position = self.size[1] * 0.55          # <-- 300

      # horizontal box for input console and status area
      hbox = Gtk::Box.new(:horizontal)
      hbox.pack_start(frame_input.set_shadow_type(:etched_in), expand: true, fill: true)
      hbox.pack_start(frame_status.set_shadow_type(:etched_in), expand: false, fill: false)
      frame_status.set_size_request(200, -1)

      # toolbar
      hbox_tool = Gtk::Box.new(:horizontal, 0)
      hbox_tool.pack_start(_create_toolbox1, expand: false, fill: false, padding: 0)
      hbox_tool.pack_end(_create_toolbox2, expand: false, fill: false, padding: 10)

      # container
      vbox_all = Gtk::Box.new(:vertical, 0)
      vbox_all.pack_start(@uimanager.get_widget("/MenuBar"), expand: false, fill: true, padding: 0)
      vbox_all.pack_start(hbox_tool, expand: false, fill: true, padding: 0)
      vbox_all.pack_start(vpaned, expand: true, fill: true, padding: 0)
      vbox_all.pack_start(hbox, expand: false, fill: false, padding: 0)

      # window
      @editor.page_focus                             # set focus to page of editor
      self.add(vbox_all)
      self.set_window_position(:center)
      self.show_all

      # handler
      self.signal_connect(:delete_event) do
        puts "clicked [x]"
        _close_page_all                              # in case of being returned 'true', signal of ':destroy' is not happend
      end

      self.signal_connect(:destroy) do
        # _quit
      end
    end

    # set menu
    private def _set_menu
      menu            = @conf.menu
      actions_menubar = @conf.actions_menubar
      actions_toggle  = @conf.actions_menubar_toggle

      menubar_group = Gtk::ActionGroup.new("menubar_group")
      menubar_group.add_actions(actions_menubar)
      @uimanager.insert_action_group(menubar_group, 0)

      toggle_group = Gtk::ActionGroup.new("toggle_group")
      toggle_group.add_toggle_actions(actions_toggle)
      @uimanager.insert_action_group(toggle_group, 0)

      @uimanager.add_ui(menu)

      @uimanager.action_groups.each do |ag|
        ag.actions.each do |a|
          a.hide_if_empty = false                                     # if true, couldn't show empty node
        end
      end

      @uimanager.get_action("/MenuBar/file/kill").sensitive = false   # disable 'kill(terminate)' item
    end

    # toolbox for toolbutton
    def _create_toolbox1
      toolbar = Gtk::Toolbar.new
      f = "#{File.expand_path(File.dirname(__FILE__))}/config/run.xpm"
      @toolitem_run = Gtk::ToolButton.new(icon_widget: Gtk::Image.new(file: f), label: @conf.messages[:exec])
      toolbar.insert(@toolitem_run, 0)
      toolbar.style = Gtk::ToolbarStyle::BOTH
      @toolitem_run.signal_connect(:clicked) {
        _exec
      }

      toolbar
    end

    # toolbox for finding function
    def _create_toolbox2
      boxf = Gtk::Box.new(:vertical)
      box  = Gtk::Box.new(:horizontal)

      f = "#{File.expand_path(File.dirname(__FILE__))}/config/find_next.xpm"
      item = Gtk::ToolButton.new(icon_widget: Gtk::Image.new(file: f))
      #item.set_icon_name("go-down")
      box.pack_end(item)
      item.signal_connect(:clicked) {
        _find_and_select(@word, :forward)
      }

      f = "#{File.expand_path(File.dirname(__FILE__))}/config/find_prev.xpm"
      item = Gtk::ToolButton.new(icon_widget: Gtk::Image.new(file: f))
      #item.set_icon_name("go-up")
      box.pack_end(item)
      item.signal_connect(:clicked) {
        _find_and_select(@word, :backward)
      }

      entry = Gtk::Entry.new
      entry.set_size_request(0, 0)
      entry.override_font(Pango::FontDescription.new("#{@conf.platform[:font][:find]}"))
      box.pack_end(entry, fill: false, expand: false, padding: 5)   # want to be minimum ...?
      entry.signal_connect(:changed) {
        @word = entry.text
      }
      entry.signal_connect("activate") {
        _find_and_select(@word, :forward)
      }
      item = Gtk::Label.new(@conf.messages[:find])
      box.pack_end(item, fill: false, expand: false, padding: 5)   # want to be minimum ...?

      boxf.pack_start(Gtk::Label.new(''), fill: false, expand: false)
      boxf.pack_start(box, fill: false, expand: false)
      boxf.pack_start(Gtk::Label.new(''), fill: false, expand: false)

      boxf
    end

    # execute
    private def _exec
      @thread = Thread.start do
        # disabled/enable menu
        @toolitem_run.sensitive = false
        @uimanager.get_action("/MenuBar/file/run").sensitive  = false
        @uimanager.get_action("/MenuBar/file/kill").sensitive = true

        begin
          dirname, basename, tabname, status = @editor.get_page_properties
          if dirname and Dir.exist?(dirname)
            # in case of already existing the file in directory
            run_dirname  = dirname                           # run at there directory
            run_filename = @editor.save_tmp(dirname)
          else
            tmp_dirname  = Dir.mktmpdir(["ruby_", "_tmp"])
            run_dirname  = tmp_dirname                       # run at temporary directory
            run_filename = @editor.save_tmp(tmp_dirname)
          end

          # save temporary file for DRb in directory for executing
          required_filename = _save_required_file(run_dirname)

          #puts "tmp_dirname       : #{tmp_dirname}"
          #puts "run_dirname       : #{run_dirname}"
          #puts "run_filename      : #{run_filename}"
          #puts "required_filename : #{required_filename}"

          # create executing command
          # cmd = %Q{ruby -E UTF-8 -r #{required_filename} -C #{run_dirname} #{run_filename}}               # -C (couldn't run about directory named by Japanese, above Ruby 2.2)
          # cmd = %Q{cd /d "#{run_dirname}" & ruby -E UTF-8 -r "#{required_filename}" #{run_filename}}      #    (couldn't delete temporary directory when process has killed)
          cmd = %Q{ruby -E UTF-8 -r "#{required_filename}" #{run_filename}}
          puts cmd

          # starting message
          @console_output.add_tail("> start: #{tabname} (#{Time.now.strftime('%H:%M:%S')})\n", "info")      # insert to bottom line
          @console_output.scroll_tail                                                                       # scroll till bottom line

          # move current directory while running, and go back when finished
          current_dir = Dir.pwd
          Dir.chdir(run_dirname)

          # run
          jpmsg = nil
          @q << io = IO.popen(cmd, err: [:child, :out])                                                     # merge stderr to stdout
          io.each do |line|
            line.gsub!(run_filename, tabname)                                                               # replace temporary file name to tab name for output
            line.gsub!("\x03\n", "")                                                                        # correspond the 'print' command which has no line-feed (delete line-feed including "\x03")
            @console_output.add_tail(line, "result")                                                        # insert to bottom line
            @console_output.scroll_tail                                                                     # scroll till bottom line
            if @uimanager.get_action("/MenuBar/option/errorjp") and
               @uimanager.get_action("/MenuBar/option/errorjp").active?
              jpmsg = Error_jp.get_msg(line) if line =~ /^#{tabname}/ or line =~ /\(.*Error\)$/
            end
          end
          if jpmsg
            @console_output.add_tail(jpmsg, "error_jp")                                                     # insert to bottom line
            @console_output.scroll_tail                                                                     # scroll till bottom line
          end

        ensure
          # close IO
          io.close

          # go back to the original directory
          Dir.chdir(current_dir)

          # ending message
          @console_output.newline            # insert line-feed when not head of line
          @console_output.add_tail("> end  : #{tabname} (#{Time.now.strftime('%H:%M:%S')})\n\n", "info")    # insert to bottom line
          @console_output.scroll_tail                                                                       # scroll till bottom line

          # delete temporary directory including files in it
          FileUtils.remove_entry_secure "#{run_dirname}/#{run_filename}"
          FileUtils.remove_entry_secure required_filename
          puts "Thread Terminate... #{tmp_dirname}"
          FileUtils.remove_entry_secure tmp_dirname if tmp_dirname                                          # couldn't delete current directory if stay here
          puts "Thread Terminate..."

          # clear the queue
          @q.clear
        end

        # enabled/disable menu
        @toolitem_run.sensitive = true
        @uimanager.get_action("/MenuBar/file/run").sensitive  = true
        @uimanager.get_action("/MenuBar/file/kill").sensitive = false
      end
    end

    # terminate
    private def _kill
      pid = (@q.empty? ? -1 : @q.pop.pid)
      if pid > 0 and @thread
        p pid
        p @thread
        puts "kill tprocess => " + pid.to_s
        if @os == :windows
          system("taskkill /f /pid #{pid}")      # terminate the process (Windows)
        else
          Process.kill(:KILL, pid)               # terminate the process (not Windows)
        end

        @thread.kill                             # kill thread
        @thread = nil

        # enabled/disable menu
        @toolitem_run.sensitive = true
        @uimanager.get_action("/MenuBar/file/run").sensitive  = true
        @uimanager.get_action("/MenuBar/file/kill").sensitive = false
      end
    end

    # code for DRb server to emulate STDIN (to be required when starting-up)
    private def _save_required_file(tmp_dirname)
      # $stdin <-- (druby) -- $in
      script = <<~"EOS"                          # exclude indent
        require 'drb/drb'
        require 'drb/acl'
        $stdout.sync = true
        $stderr.sync = true
        $stdin, $in = IO.pipe
        module Kernel
          alias_method :__print__, :print
          def print(*args)
            __print__(*args, "\\x03\\n")           # correspond the 'print' command which has no line-feed
          end
        end
        list = %w[
          deny all
          allow 127.0.0.1
        ]
        # -- <DRb::DRbConnError: An existing connection was forcibly closed by the remote host.> if use 'localhost'
        DRb.install_acl(ACL.new(list, ACL::DENY_ALLOW))
        begin
          DRb.start_service("druby://127.0.0.1:#{@drb_portno}", $in, safe_level: 1)
        rescue
        end
      EOS
      basename = "rq_#{Utility.get_uniqname}.rb"
      tmpfilepath = "#{tmp_dirname}/#{basename}"
      File.open(tmpfilepath, "w") do |fp|
        fp.puts script
      end
      return tmpfilepath                         # path of temporary file
    end

    # show properties
    private def _info
      dirname, basename, tabname, status = @editor.get_page_properties
      # show
      @console_output.add_tail("[#{tabname}]\n")
      @console_output.add_tail(" #{@conf.messages[:info_stat]} : #{status}\n")
      @console_output.add_tail(" #{@conf.messages[:info_dir]} : #{dirname}\n")
      @console_output.add_tail(" #{@conf.messages[:info_base]} : #{basename}\n\n")
      @console_output.scroll_tail                # scroll till bottom line
    end

    # show version of Ruby
    private def _ruby_ver
      thread = Thread.start do
        IO.popen("ruby -v", err: [:child, :out]) do |pipe|
          pipe.each do |line|
            @console_output.add_tail(line)       # insert to bottom line
          end
        end
       #@console_output.add_tail("\n")           # insert to bottom line (empty-line)
        @console_output.scroll_tail              # scroll till bottom line
      end
    end

    # open file
    private def _open
      dialog = Gtk::FileChooserDialog.new(
        title: @conf.messages[:dialog_open],
        parent: self,
        action: :open,
        back: nil,
        buttons: [[Gtk::Stock::OK, :accept],
                  [Gtk::Stock::CANCEL, :cancel]]
      )
      # set current directory
      if @last_dir
        # last specified directory
        dialog.current_folder = @last_dir
      else
        # desktop
        if ENV.has_key?("HOME") and Dir.exist?(ENV["HOME"] + "/Desktop")
          dialog.current_folder = ENV["HOME"] + "/Desktop"
        elsif ENV.has_key?("USERPROFILE") and Dir.exist?(ENV["USERPROFILE"] + "/Desktop")
          dialog.current_folder = ENV["USERPROFILE"] + "/Desktop"
        end
      end

      # set filters
      filter1 = Gtk::FileFilter.new
      filter2 = Gtk::FileFilter.new
      filter1.name = "Ruby Program Files (*.rb)"
      filter2.name = "All Files (*.*)"
      filter1.add_pattern('*.rb')
      filter2.add_pattern('*')
      dialog.add_filter(filter1)                          # default is first added filter
      dialog.add_filter(filter2)

      while true
        filename = nil
        res = dialog.run
        if res == :accept
          filename = dialog.filename.gsub('\\', '/')      # /foo/bar/zzz
        end

        # close dialog when canceled
        break if filename == nil

        if File.extname(filename) != ".lnk"
          puts "filename #{filename}"
          if @editor.load(filename)                       # load the file from specified directory
            @last_dir = File.dirname(filename)
          end
          break
        else
          begin
            # Windows only
            sh = WIN32OLE.new('WScript.Shell')
            lnkfile = sh.CreateShortcut(filename)         # create WshShortcut object from *.lnk file (WIN32OLE)
            if FileTest.directory?(lnkfile.TargetPath)
              dialog.current_folder = lnkfile.TargetPath  # open linked directory if link to directory (show dialog again)
            elsif FileTest.readable_real?(lnkfile.TargetPath)
              @editor.load(lnkfile.TargetPath)            # load the linked file from specified directory
              @last_dir = File.dirname(lnkfile.TargetPath)
              break
            end
          rescue
            break
          end
        end
      end
      dialog.destroy
    end

    # save file
    private def _save
      # do nothing if status is :EMPTY or :SAVED
      # overwrite silently if 'dirname' is existing directory
      # otherwise, call '_save_as'
      dirname, basename, tabname, status = @editor.get_page_properties
      puts "status #{status}  basename #{basename}  dirname #{dirname}"
      return if status == :EMPTY
      return if status == :SAVED
      if dirname and Dir.exist?(dirname) and basename
        @editor.save("#{dirname}/#{basename}")            # save the file where specified directory
      else
        _save_as                                          # show dialog for save as
      end
    end

    # save file as
    private def _save_as
      dialog = Gtk::FileChooserDialog.new(
        title: @conf.messages[:dialog_saveas],
        parent: self,
        action: :save,
        back: nil,
        buttons: [[Gtk::Stock::OK,     :accept],
                  [Gtk::Stock::CANCEL, :cancel]]
      )
      # set current directory
      if @last_dir
        # last specified directory
        dialog.current_folder = @last_dir
      else
        # desktop
        if ENV.has_key?("HOME") and Dir.exist?(ENV["HOME"] + "/Desktop")
          dialog.current_folder = ENV["HOME"] + "/Desktop"
        elsif ENV.has_key?("USERPROFILE") and Dir.exist?(ENV["USERPROFILE"] + "/Desktop")
          dialog.current_folder = ENV["USERPROFILE"] + "/Desktop"
        end
      end

      # confirm whether overwrite, when already exist file which has same name
      dialog.do_overwrite_confirmation = true
      dialog.signal_connect("confirm_overwrite") do |fc|
        #puts "confirm #{dialog.uri}"
        :confirm
      end

      # set filters
      filter1 = Gtk::FileFilter.new
      filter2 = Gtk::FileFilter.new
      filter1.name = "Ruby Program Files (*.rb)"
      filter2.name = "All Files (*.*)"
      filter1.add_pattern('*.rb')
      filter2.add_pattern('*')
      dialog.add_filter(filter1)                          # default is first added filter
      dialog.add_filter(filter2)

#      res = dialog.run
#      if res == :accept
#        puts dialog.filename
#        filename = dialog.filename.gsub('\\', '/')       # /foo/bar/zzz
#        @editor.save(filename)                           # save the file where specified directory
#      end

      while true
        filename = nil
        res = dialog.run
        if res == :accept
          filename = dialog.filename.gsub('\\', '/')      # /foo/bar/zzz
        end

        # close dialog when canceled
        break if filename == nil

        if File.extname(filename) != ".lnk"
          puts "filename #{filename}"
          @editor.save(filename)                          # save the file where specified directory
          @last_dir = File.dirname(filename)
          break
        else
          begin
            # Windows only
            sh = WIN32OLE.new('WScript.Shell')
            lnkfile = sh.CreateShortcut(filename)         # create WshShortcut object from *.lnk file (WIN32OLE)
            if FileTest.directory?(lnkfile.TargetPath)
              dialog.current_folder = lnkfile.TargetPath  # open linked directory if link to directory (show dialog again)
            elsif FileTest.readable_real?(lnkfile.TargetPath)
              @editor.save(lnkfile.TargetPath)            # save the linked file where specified directory
              @last_dir = File.dirname(lnkfile.TargetPath)
              break
            end
          rescue
            break
          end
        end
      end

      dialog.destroy
    end

    # confirmation dialog (Yes/No/Cancel)
    private def _draw_confirm_dialog(title, labeltext, parent)
      dialog = Gtk::Dialog.new(title: title, parent: parent, flags: :modal)

      dialog.child.pack_start(Gtk::Label.new(labeltext), expand: true, fill: true, padding: 30)

      dialog.add_button(Gtk::Stock::YES,    :yes)
      dialog.add_button(Gtk::Stock::NO,     :no)
      dialog.add_button(Gtk::Stock::CANCEL, :cancel)
      dialog.default_response = Gtk::ResponseType::CANCEL         # set default (= CANCEL button)
      dialog.show_all

      res = dialog.run
      dialog.destroy
      return res
    end

    # open the references
    private def _startcmd(uri)
      if uri =~ /^http/
        cmd = "#{@conf.platform[:command][:browse]} #{uri}"
      else
        # decide the relative path based on the place of script when local files
        cmd = "#{@conf.platform[:command][:browse]} #{File.expand_path(File.dirname(__FILE__))}/#{uri}"
      end

      Thread.start do
        p cmd
        system(cmd)                                   # open by default application
      end
    end

    # append page
    private def _new
      @editor.append
      @editor.page_focus                              # set focus to current page in editor
    end

    # close
    private def _close
      _close_page
      if @editor.n_pages <= 0                         # quit if all pages are closed
        _kill
        _quit
      end
    end

    # close all pages
    private def _close_page_all
      until @editor.n_pages <= 0
        return true if _close_page == :CANCEL_CLOSE   # if true, not to be destroyed when call from delete_event
      end
      _kill
      _quit
      true                                            # if true, not to be destroyed when call from delete_event
    end

    # quit
    private def _quit
      # -- pending the following codes for persistance
      # options = {}
      # @conf.option_ids.each do |o|
      #   if @uimanager.get_widget("/MenuBar/option/#{o}")
      #     options[o.to_sym] = @uimanager.get_widget("/MenuBar/option/#{o}").active?
      #   end
      # end
      # @conf.persist(options)
      Gtk.main_quit
    end

    # close page
    private def _close_page
      dirname, basename, tabname, status = @editor.get_page_properties
      if status == :UNSAVED
        # show dialog when not saved
        res = _draw_confirm_dialog("rbpad", " #{tabname} #{@conf.messages[:confirm_save]}", self)
        if    res == :yes
          if dirname and basename
            _save
          else
            _save_as
          end
          @editor.close
        elsif res == :no
          @editor.close
        else
          return :CANCEL_CLOSE
        end
      else
        # close as it is, when saved or empty
        @editor.close
      end
    end

    ###
    private def _undo         ; @editor.undo          ; end
    private def _redo         ; @editor.redo          ; end
    private def _cut          ; @editor.cut           ; end
    private def _copy         ; @editor.copy          ; end
    private def _paste        ; @editor.paste         ; end
    private def _select_all   ; @editor.select_all    ; end
    private def _clear_output ; @console_output.clear ; end

    private def _find_and_select(word, direction)
      unless @editor.find_and_select(word, direction)
        @console_output.add_tail("'#{word}' #{@conf.messages[:not_found]}\n")        # insert to bottom line
        @console_output.scroll_tail                                                  # scroll till bottom line
      end
    end

    private def _drawspaces(ag, action)
      @editor.set_draw_spaces(action.active?)
    end

    private def _blockmatch(ag, action)
      @editor.set_block_match(action.active?)
    end

    # insert block to new page (for tamplates)
    private def _load_block(statement)
      @editor.load_block(statement)
    end

  end
end

