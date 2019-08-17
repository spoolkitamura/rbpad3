
require 'gtk3'
require 'gtksourceview3'
require 'uri'

require 'rbpad/blockmatch'


module Rbpad

  class Page < Gtk::ScrolledWindow
    attr_reader :status, :dirname, :basename

    def initialize(conf, status_area)
      super()

      language                = GtkSource::LanguageManager.new.get_language('ruby')
      buffer                  = GtkSource::Buffer.new(language)
      buffer.highlight_syntax = true      # syntax highlight

      @conf     = conf
      schememgr = GtkSource::StyleSchemeManager.new.set_search_path([@conf.sourceview])
      #p schememgr.scheme_ids
      #p schememgr.search_path

      scheme = schememgr.get_scheme("rbpad")
      buffer.set_style_scheme(scheme)

      @view = GtkSource::View.new(buffer)
      @view.override_font(Pango::FontDescription.new("#{@conf.platform[:font][:page]}"))
      @view.left_margin            = 6
      @view.pixels_above_lines     = 1
      @view.pixels_below_lines     = 1
      @view.accepts_tab            = false     # 'TAB' is used for moving focus
      @view.editable               = true      # editable
      @view.cursor_visible         = true      # show cursor
      @view.show_line_numbers      = true      # show line number
      @view.auto_indent            = true      # auto indent
      @view.highlight_current_line = true      # show current line with highlight

      self.add(@view)

      @status      = :EMPTY
      @dirname     = nil
      @basename    = nil
      @status_area = status_area

      attr = {
        color:  scheme.get_style("def:comment").foreground.downcase,
        bold:   scheme.get_style("def:comment").bold?,
        italic: scheme.get_style("def:comment").italic?
      }
      @bm = BlockMatch.new(@view, attr)

      _display_status                          # show status

      @view.drag_dest_set(Gtk::DestDefaults::MOTION |
                          Gtk::DestDefaults::HIGHLIGHT |
                          Gtk::DestDefaults::DROP,
                          [["text/uri-list", :other_app, 49334]],
                          Gdk::DragAction::COPY | 
                          Gdk::DragAction::MOVE)

      @view.signal_connect(:drag_data_received) do |widget, context, x, y, data, info, time|
        # decode the data which is uri encoded,
        # and process each file from multi files list
        if @last_received_time != time   # [BUG?] Signal is sent dupulicate including last time data since 2nd operation, isn't it ?
          data.uris.each do |uri|
            dec_uri = URI.decode(uri)
            if /cygwin|mingw|mswin/ === RUBY_PLATFORM and /file:\/\/\/[A-Z]:/ === dec_uri          # UNC is formatted like file://host/path/file
              filename = dec_uri.sub('file:///', '')   # Windows      : e.g. file:/// (file:///C:/foo/bar.rb --> C:/foo/bar.rb)
            else
              filename = dec_uri.sub('file://', '')    # Linux, macOS : e.g. file://  (file:///home/foo/bar.rb --> /home/foo/bar.rb)
            end
            self.parent.load(filename)
          end
          @last_received_time = time
        end
      end

      @view.signal_connect(:button_release_event) do
        # by pointing mouse cursor
        _display_status
        @bm.scan if @block_match
        false                                          # if true, event about selecting range by mouse pointer is happend
      end

      @view.signal_connect_after(:move_cursor) do |widget, step, count, extend_selection|
        _display_status
        @bm.scan if @block_match
      end

      @view.buffer.signal_connect(:changed) do |widget|
        @status = :UNSAVED                             # update status of editing
        _display_status
      end
    end

    def destroy
      self.instance_variables.each do |v|
        remove_instance_variable(v)
      end
    end

    def undo
      @view.signal_emit(:undo)
    end

    def redo
      @view.signal_emit(:redo)
    end

    def cut
      @view.signal_emit(:cut_clipboard)
    end

    def copy
      @view.signal_emit(:copy_clipboard)
    end

    def paste
      @view.signal_emit(:paste_clipboard)                       # scroll till bottom of pasted line
    end

    def select_all
      @view.signal_emit(:select_all, true)
    end

    def set_draw_spaces(status)
      if status
        @view.draw_spaces = GtkSource::DrawSpacesFlags::SPACE   # show space character
      else
        @view.draw_spaces = 0
      end
    end

    def set_block_match(status)
      @block_match = status
      if status
        @bm.scan
      else
        @bm.clear
      end
    end

    def find_and_select(word, direction)
      return true unless word
      @view.set_focus(true)
      iter = @view.buffer.get_iter_at(mark: @view.buffer.get_mark("insert"))
      if direction == :forward
        if @view.buffer.get_iter_at(mark: @view.buffer.get_mark("selection_bound")).offset > @view.buffer.get_iter_at(mark: @view.buffer.get_mark("insert")).offset
          # avoid duplicate hits of the same word
          # when reversing the search direction
          iter = @view.buffer.get_iter_at(mark: @view.buffer.get_mark("selection_bound"))
        end
        match_iters = iter.forward_search(word, :text_only)
        next_iter = [match_iters[1], match_iters[0]] if match_iters
      else
        if @view.buffer.get_iter_at(mark: @view.buffer.get_mark("selection_bound")).offset < @view.buffer.get_iter_at(mark: @view.buffer.get_mark("insert")).offset
          # avoid duplicate hits of the same word
          # when reversing the search direction
          iter = @view.buffer.get_iter_at(mark: @view.buffer.get_mark("selection_bound"))
        end
        match_iters = iter.backward_search(word, :text_only)
        next_iter = match_iters if match_iters
      end
      if match_iters
        @view.buffer.place_cursor(next_iter[0])
        @view.scroll_mark_onscreen(@view.buffer.get_mark("insert"))
        @view.buffer.move_mark(@view.buffer.get_mark("selection_bound"), next_iter[1])
        _display_status
        @bm.scan if @block_match
        true
      else
        false
      end
    end

    # insert text block with indent at cursor place
    def insert_block(text, cursor = nil)
      mark = @view.buffer.selection_bound                 # get mark of cursor place
      iter = @view.buffer.get_iter_at(mark: mark)         # get iter from mark
      text.gsub!("\n", "\n#{" " * iter.line_offset}")     # adjust indent of text (add space after line-feed)
      @view.buffer.insert_at_cursor(text)                 # insert text
      @view.scroll_to_mark(mark, 0, false, 0, 1)          # move to mark
      if cursor == :start
        @view.buffer.place_cursor(@view.buffer.start_iter)
      end
      _display_status
    end

    # save file
    def save(filename, temporary = false)
      content  = @view.buffer.text
      File.open(filename, "wb:utf-8") do |fp|
        fp.puts content
      end

      unless temporary
        @status   = :SAVED
        @dirname  = File.dirname(filename)
        @basename = File.basename(filename)
      end
      _display_status
    end

    # load file
    def load(filename, template = false)
      begin
        File.open(filename, "rb:utf-8") do |file|
          # replace incorrect bytes to 'U+FFFD'
          content = file.read.scrub
          @view.buffer.insert(@view.buffer.end_iter, content)
        end

        if template
          @status = :UNSAVED
        else
          @status = :SAVED
          @dirname  = File.dirname(filename)
          @basename = File.basename(filename)
        end

        @view.buffer.place_cursor(@view.buffer.start_iter)
        _display_status
        true
      rescue
        # when has read binary file, etc
        false
      end
    end

    # set focus
    def set_focus
      @view.set_focus(true)
    end

    # show information
    def display_status
      _display_status
    end

    # show information at status area (line, columun, saving status)
    private def _display_status(movement_step = nil, count = 0)
      mark = @view.buffer.selection_bound           # get the mark at the cursor position
      iter = @view.buffer.get_iter_at(mark: mark)

      stat = @conf.messages[:status_saved]
      stat = @conf.messages[:status_unsaved] if @status == :UNSAVED
      # e.g. "%5L%4C  (UNSAVED)"
      format = "%5d#{@conf.messages[:status_pos_l]}%4d#{@conf.messages[:status_pos_c]}    %-10s"
      @status_area.text = format % [iter.line + 1, iter.line_offset + 1, stat]
    end

  end
end

