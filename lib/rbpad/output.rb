
require 'gtk3'


module Rbpad

  class ConsoleOutput < Gtk::ScrolledWindow
    def initialize(conf)
      super()
      @view   = Gtk::TextView.new
      @view.override_font(Pango::FontDescription.new("#{conf.platform[:font][:output]}"))
      @view.left_margin        = 6
      @view.pixels_above_lines = 1
      @view.pixels_below_lines = 1
      @view.accepts_tab        = false                            # 'TAB' is used for moving focus
      @view.buffer.create_tag('info',     {foreground: 'gray'})
      @view.buffer.create_tag('result',   {weight: 600})          # SEMI-BOLD
      @view.buffer.create_tag('error_jp', {foreground: 'red'})
      @view.set_editable(false)
      self.add(@view)
    end

    # line feed other than at the beginning of a line
    def newline
      @view.buffer.insert(@view.buffer.end_iter, "\n") if @view.buffer.end_iter.line_offset != 0
    end

    # insert text at bottom line
    def add_tail(text, tag = nil)
      @view.buffer.insert(@view.buffer.end_iter, text.scrub)
      unless tag == nil                                           # format by specified tag
        iter_s = @view.buffer.get_iter_at(offset: @view.buffer.end_iter.offset - text.size)
        iter_e = @view.buffer.end_iter
        @view.buffer.apply_tag(tag, iter_s, iter_e)
      end
    end

    # scroll to bottom line
    def scroll_tail
      mark = @view.buffer.create_mark(nil, @view.buffer.end_iter, true)
      @view.scroll_to_mark(mark, 0, false, 0, 1)                  # ('scroll_to_iter' does not work)
    end

    # clear
    def clear
      @view.buffer.delete(@view.buffer.start_iter, @view.buffer.end_iter)
    end
  end

end

