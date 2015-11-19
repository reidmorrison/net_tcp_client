require 'socket'
require 'net/tcp_client/version'
require 'net/tcp_client/exceptions'
require 'net/tcp_client/tcp_client'

# @formatter:off
module Net
  class TCPClient
    autoload :Socket,    'net/tcp_client/socket'
    module Policy
      autoload :Base,    'net/tcp_client/policy/base.rb'
      autoload :Custom,  'net/tcp_client/policy/custom.rb'
      autoload :Ordered, 'net/tcp_client/policy/ordered.rb'
      autoload :Random,  'net/tcp_client/policy/random.rb'
    end
  end
end
