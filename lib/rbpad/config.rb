
require 'gtk3'
require 'rexml/document'


module Rbpad

  class Config
    attr_reader :menu,
                :actions_menubar,
                :actions_menubar_toggle,
                :messages,
                :platform,
                :sourceview

    def initialize(context, os, lang = :jp)
      @os                            = os
      @lang                          = lang

      current_dir                    = File.expand_path(File.dirname(__FILE__))
      @conf_menu                     = "#{current_dir}/config/menu.xml"
      @conf_actions_menubar          = "#{current_dir}/config/actions_menubar.xml"
      @conf_actions_menubar_template = "#{current_dir}/config/actions_menubar_template.xml"
      @conf_actions_menubar_toggle   = "#{current_dir}/config/actions_menubar_toggle.xml"
      @conf_messages                 = "#{current_dir}/config/messages.xml"         # fixed words in jp/en
      @conf_platform                 = "#{current_dir}/config/platform.xml"         # command and font on win/mac/linux

      @sourceview                    = "#{current_dir}/config/sourceview.xml"       # for Syntax Highlight

      _read_menu
      _read_actions_menubar(context)
      _read_actions_menubar_toggle(context)
      _read_messages
      _read_platform
    end

    private def _read_menu
      xmldoc = nil
      File.open(@conf_menu) do |fp|
        xmldoc = REXML::Document.new(fp)
      end

      xmldoc.elements.each('ui/menubar/menu/menuitem') do |e|
        if Regexp.compile(@lang.to_s[0]) !~ e.attributes['lang']
          puts "#{e.attributes['action']} #{e.attributes['lang']}"
          puts e.xpath
          xmldoc.delete_element(e.xpath)
        end
      end

      xmldoc.elements.each('ui/menubar/menu/separator') do |e|
        if Regexp.compile(@lang.to_s[0]) !~ e.attributes['lang']
          puts "#{e.attributes['action']} #{e.attributes['lang']}"
          puts e.xpath
          xmldoc.delete_element(e.xpath)
        end
      end
      @menu = xmldoc.root.to_s
    end

    private def _read_actions_menubar(context)
      @actions_menubar = []

      xmldoc = nil
      File.open(@conf_actions_menubar) do |fp|
        xmldoc = REXML::Document.new(fp)
      end

      xmldoc.elements.each('actions/menubar_action/branch') do |e|        # menu (parent or node)
        @actions_menubar << [e.attributes['id'],
                             nil, 
                             (@lang == :jp ? e.attributes['desc_j'] : e.attributes['desc_e']),
                             nil,
                             nil,
                             Proc.new{ }]
      end

      xmldoc.elements.each('actions/menubar_action/menuitem') do |e|      # menu item
        @actions_menubar << [e.attributes['id'],
                             nil,
                             (@lang == :jp ? e.attributes['desc_j'] : e.attributes['desc_e']),
                             _acckey(e.attributes['acckey']),
                             nil,
                             context.eval(e.attributes['proc']) ]
      end

      xmldoc.elements.each('actions/menubar_action/uri') do |e|           # URI refer item
        @actions_menubar << [e.attributes['id'],
                             nil,
                             (@lang == :jp ? e.attributes['desc_j'] : e.attributes['desc_e']),
                             _acckey(e.attributes['acckey']),
                             nil,
                             context.eval((@lang == :jp ? e.attributes['proc_j'] : e.attributes['proc_e'])) ]
      end

      xmldoc = nil
      File.open(@conf_actions_menubar_template) do |fp|
        xmldoc = REXML::Document.new(fp)
      end

      xmldoc.elements.each('actions/menubar_action/template') do |e|      # template item
        @actions_menubar << [e.attributes['id'],
                             nil,
                             (@lang == :jp ? e.attributes['desc_j'] : e.attributes['desc_e']),
                             _acckey(e.attributes['acckey']),
                             nil,
                             context.eval(%Q(Proc.new{_load_block("#{e.text.sub(/^\n/, '').chomp}")})) ]   # remove only the newline inserted at the beginning
      end
    end

    private def _read_actions_menubar_toggle(context)
      @actions_menubar_toggle  = []

      File.open(@conf_actions_menubar_toggle) do |fp|
        xmldoc = REXML::Document.new(fp)

        xmldoc.elements.each('actions/toggle_action/checkitem') do |e|    # check item
          @actions_menubar_toggle << [e.attributes['id'],
                                      nil,
                                      (@lang == :jp ? e.elements['desc_j'].text : e.elements['desc_e'].text),
                                      _acckey(e.elements['acckey'].text),
                                      nil,
                                      context.eval(e.elements['proc'].text),
                                      context.eval(e.attributes['value']) ]
        end
      end
    end

    private def _read_messages
      @messages = {}
      File.open(@conf_messages) do |fp|
        xmldoc = REXML::Document.new(fp)
        xmldoc.elements.each('messages/string') do |e|
          @messages[e.attributes['id'].to_sym] = (@lang == :jp ? e.elements['jp'].text : e.elements['en'].text)
        end
      end
    end

    private def _read_platform
      @platform = {}
      File.open(@conf_platform) do |fp|
        xmldoc = REXML::Document.new(fp)

        hash = {}
        xmldoc.elements.each('platform/command') do |e|
          hash[e.attributes['id'].to_sym] = (case @os
                                             when :windows
                                               e.elements['win'].text
                                             when :mac
                                               e.elements['mac'].text
                                             when :linux
                                               e.elements['linux'].text
                                             end)
        end
        @platform[:command] = hash

        hash = {}
        xmldoc.elements.each('platform/font') do |e|
          hash[e.attributes['id'].to_sym] = (case @os
                                             when :windows
                                               e.elements['win'].text
                                             when :mac
                                               e.elements['mac'].text
                                             when :linux
                                               e.elements['linux'].text
                                             end)
        end
        @platform[:font] = hash
      end
    end

    private def _acckey(key_path)
      # convert key defincation for accelerator ('___' --> 'meta' or 'control')
      if @os == :mac
        s = key_path.sub(/___/, 'meta')
      else
        s = key_path.sub(/___/, 'control')
      end
      s
    end

    # option IDs
    def option_ids
      ids = []
      @actions_menubar_toggle.each do |item|
        ids << item[0]   # attributes['id'] of checkitem
      end
      ids
    end

    # persist the value of option item
    def persist(param)
      xmldoc = nil
      File.open(@conf_actions_menubar_toggle) do |fp|
        xmldoc = REXML::Document.new(fp)
      end
      param.keys.each do |key|
        xmldoc.elements.each("actions/toggle_action/checkitem") do |e|
          if key.to_s == e.attributes['id']
            e.attributes['value'] = param[key]
            break
          end
        end
      end
      begin
        File.open(@conf_actions_menubar_toggle, 'w+') do |file|
          xmldoc.write(output: file, indent: -1)
        end
      rescue => e
        puts e.inspect
      end
    end

  end
end

