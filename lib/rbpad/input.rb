
require 'gtk3'
require 'drb/drb'


module Rbpad

  class ConsoleInput < Gtk::Entry
    def initialize(conf, drb_portno)
      super()                             # no argument
      self.override_font(Pango::FontDescription.new("#{conf.platform[:font][:input]}"))
      self.signal_connect("activate") do
        text = self.text
        self.text = ""                    # clear
        puts "Entry contents: #{text}"
        begin
          cl = DRbObject.new_with_uri("druby://127.0.0.1:#{drb_portno}")
          cl.puts(text)                   # sent to DRb server (Emulate STDIN)
        rescue => e
          p e
        end
      end
    end
  end

end

