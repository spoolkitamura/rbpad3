
require 'gtk3'

require 'rbpad/page'
require 'rbpad/util'


module Rbpad

  class Editor < Gtk::Notebook

    def initialize(conf, status_area)
      super()
      @conf        = conf
      @status_area = status_area
      @next_pageno = 0
      _append_page
      __debug_status

      self.scrollable   = true
      self.enable_popup = true

      self.signal_connect("switch-page") do |widget, page, num_page|
        puts "switch page #{widget.page} --> #{num_page}  (n_pages = #{widget.n_pages})"
        self.get_nth_page(num_page).display_status
        self.get_nth_page(num_page).set_draw_spaces(@draw_spaces)
        self.get_nth_page(num_page).set_block_match(@block_match)
      end
    end

    # set focus to the page
    def page_focus
      self.get_nth_page(self.page).set_focus
    end

    # load statements to new page
    def load_block(statement)
      editor_page = _append_page
      editor_page.insert_block(statement, :start)
    end

    # save temporary file to specified directory
    def save_tmp(dirname)
      editor_page = self.get_nth_page(self.page)
      basename = "rs_#{Utility.get_uniqname}.rb"
      filename = "#{dirname}/#{basename}"
      editor_page.save(filename, true)
      return basename
    end

    # save the file
    def save(filename)
      editor_page   = self.get_nth_page(self.page)
      p editor_page
      self.get_tab_label(editor_page).text = File.basename(filename)   # File.basename(filename, ".*")
      editor_page.save(filename)
      __debug_status
    end

    # load the file
    def load(filename)
      return if FileTest.directory?(filename)
      tabname = File.basename(filename)   # File.basename(filename, ".*")
      dirname = File.dirname(filename)
      editor_page = _append_page(dirname, filename, tabname)
      unless editor_page.load(filename)
        self.remove_page(self.page)
        return false
      end
      __debug_status
      true
    end

    # close the page
    def close
      self.remove_page(self.page)
      __debug_status
    end

    # append the new page
    def append
      _append_page
      __debug_status
    end

    # append the new page (private)
    private def _append_page(dirname = nil, filename = nil, tabname = nil)
      editor_page = Page.new(@conf, @status_area)
      editor_page.set_draw_spaces(@draw_spaces)
      editor_page.set_block_match(@block_match)
      tabname ||= "program#{@next_pageno}"
      @next_pageno += 1
      self.insert_page(editor_page, Gtk::Label.new(tabname), self.n_pages)
      self.show_all
      self.page = self.n_pages - 1   # show the inserted page (it must be set after 'show_all')

      return editor_page
    end

    # get the properties of current page
    def get_page_properties
      editor_page   = self.get_nth_page(self.page)
      return editor_page.dirname, editor_page.basename, self.get_tab_label(editor_page).text, editor_page.status
    end

    def undo       ; self.get_nth_page(self.page).undo       ; end
    def redo       ; self.get_nth_page(self.page).redo       ; end
    def cut        ; self.get_nth_page(self.page).cut        ; end
    def copy       ; self.get_nth_page(self.page).copy       ; end
    def paste      ; self.get_nth_page(self.page).paste      ; end
    def select_all ; self.get_nth_page(self.page).select_all ; end

    def find_and_select(word, direction)
      self.get_nth_page(self.page).find_and_select(word, direction)
    end

    def set_draw_spaces(status)
      self.get_nth_page(self.page).set_draw_spaces(status)
      @draw_spaces = status
    end

    def set_block_match(status)
      self.get_nth_page(self.page).set_block_match(status)
      @block_match = status
    end

    private def __debug_status
      puts "next_pageno : #{@next_pageno}"
      if self.n_pages == 0
        puts "[EMPTY]"
      else
        self.n_pages.times do |i|
          editor_page = self.get_nth_page(i)
          puts "#{i} : #{editor_page.dirname}  #{editor_page.basename}  #{self.get_tab_label(editor_page).text}  #{editor_page.status}"
        end
      end
    end

  end
end

