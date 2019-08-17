
module Rbpad

  module Error_jp
    module_function def get_msg(line)
      /(.*):(\d+)/ =~ line
      name = $1
      pos  = $2
      msg_pos     = "ファイル #{name} の #{pos}行目でエラーが発生しました。"
      msg_content = "(詳細情報は不明です)"
      if /syntax error/ =~ line
        msg_content = "syntax error"
        if    /unexpected end-of-input/ =~ line
          msg_content = %Q(プログラムの構文が途中で終わっています。)
        elsif /unexpected (keyword_)?end/ =~ line
          msg_content = %Q('end'で終わるブロックの対応が不完全です。)
        elsif /unexpected tIDENTIFIER/ =~ line
          msg_content = %Q(全角文字などの使用できない文字が混ざっています。)
        elsif /unexpected t(.*),/ =~ line
          msg_content = %Q(予期しない #{$1} が混ざっています。)
        elsif /unexpected (.*)/ =~ line
          msg_content = %Q(#{$1} という正しくないキーワードが使われています。)
        end
      elsif /\(NameError\)/ =~ line
        msg_content = "NameError"
        if    /undefined local variable or method (.*?) / =~ line
          msg_content = %Q(#{$1} という名前の変数またはメソッドが定義されていないか、タイプミスの可能性があります。)
        elsif /uninitialized constant (.*?) / =~ line
          msg_content = %Q(定数 #{$1} の値が初期化されていません。)
        end
      elsif /\(NoMethodError\)/ =~ line
        msg_content = "NoMethodError"
        if    /undefined method (.*) for (.*):(.*?) / =~ line
          msg_content = %Q(#{$3} の #{$2} には #{$1} というメソッドは定義されていません。)
        end
      elsif /\(LoadError\)/ =~ line
        msg_content = "ロードできません。"
        if    /cannot load such file \-\- (.*) /=~ line
          msg_content = %Q(#{$1} というファイルが見つからないのでロードできません。)
        end
      elsif /\(ArgumentError\)/ =~ line
        msg_content = "ArgumentError"
        if    /wrong number of arguments/ =~ line
          msg_content = %Q(メソッドに渡した引数の個数が正しくありません。)
        elsif /must be positive/ =~ line
          msg_content = %Q(引数には正(プラス)の値を渡してください。)
        elsif /must not be negative/ =~ line
          msg_content = %Q(引数には負(マイナス)以外の値を渡してください。)
        end
      elsif /\(TypeError\)/ =~ line
        msg_content = "TypeError"
        if   /can't convert (.*) into (.*) \(/ =~ line
          msg_content = %Q(引数には #{$1} ではなく #{$2} を渡してください。)
        end
      else
        if    /unterminated string/ =~ line
          msg_content = %Q(文字列が '' や "" で閉じられていません。)
        elsif /unterminated regexp/ =~ line
          msg_content = %Q(正規表現が // で閉じられていません。)
        elsif /class\/module name must be CONSTANT/ =~ line
          msg_content = %Q(クラスやモジュールの名前は大文字で始めてください。)
        elsif /No such file or directory @ rb_sysopen - (.*) / =~ line
          msg_content = %Q(#{$1} というファイルまたはディレクトリ(フォルダ)は存在しないため開くことができません。)
        elsif /Invalid argument @ rb_sysopen - (.*) / =~ line
          msg_content = %Q(#{$1} というファイル名は不正なため開くことができません。)
        elsif /Is a directory @ rb_sysopen - (.*) / =~ line
          msg_content = %Q(#{$1} はディレクトリ(フォルダ)のため開くことができません。)
        end
      end
      "#{msg_pos}\n#{msg_content}"
    end
  end

end




if $0 == __FILE__

  require 'fileutils'

  def run(file)
    cmd = %Q{ruby -E UTF-8 #{file}}
    io = IO.popen(cmd, err: [:child, :out])
    puts "\n[message]"
    jp = nil
    io.each do |line|
      puts line
      jp = Rbpad::Error_jp.get_msg(line) if line =~ /^#{File.basename(file)}/ or line =~ /\(.*Error\)$/
    end
    puts jp if jp
  end

  def make(cmd)
    puts "---------------------------------------------------"
    puts "[script]"
    puts cmd
    cmd
  end


  cmd = [
    #
    # --- syntax error
    #
    %Q!x = !,
    %Q!a = (1 + 2) * (3 + 4!,
    %Q!.to_i!,
    %Q![1, 2, 3].each do!,
    %Q![1, 2, 3].each do |x|!,
    %Q!=begin!,
    %Q!if true!,
    %Q!if!,
    %Q!if\nend!,
    %Q!Class Foo\nend!,
    %Q!class Foo << Array\nend!,
    %Q!a = 100　!,
    %Q!a = [1,\n2,\n3\n4]!,
    #
    # --- NameError
    #
    %Q!foo!,
    %Q!puts v!,
    %Q!result = true\nputs reslt!,
    %Q!puts V!,
    #
    # --- NoMethodError
    #
    %Q![1, 2, 3].foo!,
    %Q!a = []\nif a < 100\n  puts "OK"\nend!,
    %Q!/\d/.match("abc").size!,
    %Q!Math.foo!,
    #
    # --- LoadError
    #
    %Q!require 'foo'!,
    %Q!require_relative 'foo'!,
    %Q!load 'foo.rb'!,
    #
    # --- ArgumentError
    #
    %Q!puts Math.sin!,
    %Q!puts Math.sin(0, 0, 0)!,
    %Q!sleep -1!,
    #
    # --- TypeError
    #
    %Q!puts Math.sin('rad')!,
    %Q!sleep ""!,
    %Q!sleep nil!,
    #
    # --- etc.
    #
    %Q!puts 'p!,
    %Q!puts p"!,
    %Q!/3!,
    %Q!class foo\nend!,
    %Q!File.read('aaa')!,
    %Q!File.read('???')!,
    %Q!File.read('.')!,
  ]


  Encoding.default_external = 'UTF-8'

  cmd.each do |c|
    cc = make(c)
    filename = 'program0.rb'
    File.write(filename, cc)
    run(filename)
    FileUtils.rm(filename)
  end

end

