
module Rbpad

  module Utility
    module_function def get_uniqname
      # generate a random 8-character string
      (1..8).map {
        [*'A'..'Z', *'a'..'z', *'0'..'9'].sample
      }.join
    end

    module_function def get_os
      (
        host_os = RbConfig::CONFIG['host_os']
        case host_os
        when /mswin|msys|mingw|cygwin|bccwin|wince|emc/
          :windows
        when /darwin|mac os/
          :mac
        when /linux/
          :linux
        else
          :unknown
        end
      )
    end
  end

end

