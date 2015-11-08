require 'socket'
require_relative 'simple_tcp_server'
require 'openssl'

def ssl_file_path(name)
  File.join(File.dirname(__FILE__), 'ssl_files', name)
end

class SimpleSSLServer < SimpleTCPServer
  attr_reader :port, :cert, :key, :ca_file
  def initialize(port = 2000, name = 'ssl', cert, key, cafile)
    @cert = cert
    @key = key
    @ca_file = cafile
    super(port, name)
  end

  def start(port)
    context = OpenSSL::SSL::SSLContext.new
    context.set_params(ca_file: @ca_file)
    context.cert = OpenSSL::X509::Certificate.new(File.open(@cert))
    context.key  = OpenSSL::PKey::RSA.new(File.open(@key))
    self.server  = OpenSSL::SSL::SSLServer.new(TCPServer.open(port), context)
    self.thread  = Thread.new do
      loop do
        logger.debug 'Waiting for a client to connect'

        # Wait for a client to connect
        on_request(server.accept)
      end
    end
  end
end

if $0 == __FILE__
  SemanticLogger.default_level = :trace
  SemanticLogger.add_appender(STDOUT)
  server = SimpleSSLServer.new(
    2000,
    ssl_file_path('localhost-server.pem'),
    ssl_file_path('localhost-server-key.pem'),
    ssl_file_path('ca.pem'))
  server.thread.join
end
