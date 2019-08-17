=begin
    'rbpad'
      Copyright (c) 2018 Koki Kitamura
      Released under the MIT license
      https://opensource.org/licenses/mit-license.php
=end

require 'gtk3'
require 'optparse'

require 'rbpad/pad'

Encoding.default_external = 'UTF-8'

opts = ARGV.getopts('ex')

lang = (opts['e'] ? :en : :jp)           # :jp or :en

if opts['x']
  pad = Rbpad::Pad.new(lang, 0, 0)       # maximized
else
  if ARGV.size >= 2
    w = ARGV[0].to_i
    h = ARGV[1].to_i
    pad = Rbpad::Pad.new(lang, w, h)     # specified
  else
    pad = Rbpad::Pad.new(lang)           # default
  end
end

Gtk.main

