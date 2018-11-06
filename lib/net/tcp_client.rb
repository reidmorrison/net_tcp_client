require 'socket'
# Load SemanticLogger if available
begin
  require 'semantic_logger'
rescue LoadError
end
require 'net/tcp_client/version'
require 'net/tcp_client/address'
require 'net/tcp_client/exceptions'
require 'net/tcp_client/tcp_client'

# @formatter:off
module Net
  class TCPClient
    module Policy
      autoload :Base,    'net/tcp_client/policy/base.rb'
      autoload :Custom,  'net/tcp_client/policy/custom.rb'
      autoload :Ordered, 'net/tcp_client/policy/ordered.rb'
      autoload :Random,  'net/tcp_client/policy/random.rb'
    end
  end
end
