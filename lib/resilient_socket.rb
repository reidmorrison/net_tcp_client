require 'thread'
require 'socket'
require 'semantic_logger'

require 'resilient_socket/version'
require 'resilient_socket/exceptions'
module ResilientSocket
  autoload :TCPClient, 'resilient_socket/tcp_client'
end
