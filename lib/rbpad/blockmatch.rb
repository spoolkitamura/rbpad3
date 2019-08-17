
require 'gtk3'
require 'gtksourceview3'


module Rbpad

  class BlockMatch
    def initialize(textview, attr)
      @textview = textview
      @color      = attr[:color]     # attribute 'color'  of Comment line
      @bold       = attr[:bold]      # attribute 'bold'   of Comment line
      @italic     = attr[:italic]    # attribute 'italic' of Comment line
      @match_tag  = @textview.buffer.create_tag(nil, background_gdk: Gdk::Color.new(0xe0 * 0xff, 0xe0 * 0xff, 0xe0 * 0xff))
    end

    private def _indent_level(statement, iter)
      return Float::INFINITY if statement =~ /\A\s*\z/      # indent levels of blank line is considered infinite
      /\A(\s*)/ =~ statement
      level = ($1 ? $1.length : 0)                          # indent level
      if _comment?(iter, level)
        return Float::INFINITY                              # indent levels of comment line is considered infinite
      else
        return level
      end
    end

    private def _start(text)
      # must be beginning of line        :  if, unless, case, class, module, while, until, for
      # not have to be beginning of line :  begin, def, do
      # (?:) :  not capture in ()
      pattern = /(?:\A(\s*)(?:if|unless|case|class|module|while|until|for)|(\A|\s+)(?:begin|def|do))(?:\z|\s+)/

      pos = (pattern =~ text)
      if pos
        pos + ($1 ? $1.length : 0) + ($2 ? $2.length : 0)   # position of keyword from beginning of line
      else
        nil
      end
    end

    private def _end(text)
      pattern = /(\A|\s+)(end)(\z|\s+)/
      pos = (pattern =~ text)
      if pos
        pos + ($1 ? $1.length : 0)                          # position of keyword from beginning of line
      else
        nil
      end
    end

    private def _comment?(iter, pos)
      iter_check = iter.clone
      iter_check.set_line_offset(pos)
      iter_check.tags.each do |t|
        tag_color  = t.foreground_gdk.to_s.downcase
        tag_color  = tag_color[0..2] + tag_color[5..6] + tag_color[9..10]   # #rrrrggggbbbb to #rrggbb
        tag_bold   = (t.weight == 700)
        tag_italic = (t.style  == :italic)
        #puts "#{tag_color} #{@color} #{tag_bold} #{tag_italic}"

        return true if (tag_color  == @color and
                        tag_bold   == @bold  and
                        tag_italic == @italic)   # #rrggbb
      end
      false
    end

    def status
      puts @color
      puts @bold
      puts @italic
    end

    def scan
      # ignore the multi statement line
      mark = @textview.buffer.selection_bound             # get the mark of cursor position
      iter = @textview.buffer.get_iter_at(mark: mark)

      iter_s = iter.clone
      iter_s.set_line_offset(0)                           # beginning of cursor line
      iter_e   = iter.clone
      iter_e.forward_lines(1)                             # end of cursor line

      iter_s_block = nil
      iter_e_block = nil

      current_line = @textview.buffer.get_text(iter_s, iter_e, false)

      if (pos = _start(current_line)) and ! _end(current_line)
        iter_s_block = iter_s.clone

        if ! _comment?(iter_s, pos)
          current_level = _indent_level(current_line, iter_s)
          begin
            res_s = iter_s.forward_lines(1)
            res_e = iter_e.forward_lines(1)
            next_line = @textview.buffer.get_text(iter_s, iter_e, false)
            next_level = _indent_level(next_line, iter_s)
            #puts "#{current_level} #{next_level}"
            if current_level == next_level and _end(next_line)
              iter_e_block = iter_e.clone
              break
            end
          end until current_level > next_level or res_e == false                # indent unmatch or bottom of buffer
        end
      elsif (pos = _end(current_line)) and ! _start(current_line)
        iter_e_block = iter_e.clone
        if ! _comment?(iter_s, pos)
          current_level = _indent_level(current_line, iter_s)
          begin
            res_s = iter_s.backward_lines(1)
            res_e = iter_e.backward_lines(1)
            prev_line = @textview.buffer.get_text(iter_s, iter_e, false)
            prev_level = _indent_level(prev_line, iter_s)
            if current_level == prev_level and _start(prev_line)
              iter_s_block = iter_s.clone
              break
            end
          end until current_level > prev_level or res_s == false                # indent unmatch or top of buffer
        end
      end

      @textview.buffer.remove_tag(@match_tag, @textview.buffer.start_iter, @textview.buffer.end_iter)   # Clear @tag
      if iter_s_block and iter_e_block
        @textview.buffer.apply_tag(@match_tag, iter_s_block, iter_e_block)      # fill
      end
    end

    def clear
      @textview.buffer.remove_tag(@match_tag, @textview.buffer.start_iter, @textview.buffer.end_iter)   # Clear @tag
    end

  end
end

