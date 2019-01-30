require 'socket'
require 'openssl'
require 'bson'
require 'semantic_logger'

# Read the bson document, returning nil if the IO is closed
# before receiving any data or a complete BSON document
def read_bson_document(io)
  bytebuf = BSON::ByteBuffer.new
  # Read 4 byte size of following BSON document
  bytes = io.read(4)
  return unless bytes
  # Read BSON document
  sz = bytes.unpack("V")[0]
  bytebuf.put_bytes(bytes)
  bytes = io.read(sz - 4)
  return unless bytes
  bytebuf.put_bytes(bytes)
  return Hash.from_bson(bytebuf)
end

def ssl_file_path(name)
  File.join(File.dirname(__FILE__), 'ssl_files', name)
end

# Simple single threaded server for testing purposes using a local socket
# Sends and receives BSON Messages
class SimpleTCPServer
  include SemanticLogger::Loggable
  attr_accessor :thread, :server
  attr_reader :port, :name, :ssl

  def initialize(options = {})
    @port = (options[:port] || 2000).to_i
    @name = options[:name] || 'tcp'
    @ssl  = options[:ssl] || false
    start
  end

  def start
    tcp_server = TCPServer.open(port)

    if ssl
      context = OpenSSL::SSL::SSLContext.new.tap do |context|
        context.set_params(ssl)
        context.servername_cb = proc {|socket, name|
          if name == 'localhost'
            OpenSSL::SSL::SSLContext.new.tap do |new_context|
              new_context.cert = OpenSSL::X509::Certificate.new(File.open(ssl_file_path('localhost-server.pem')))
              new_context.key = OpenSSL::PKey::RSA.new(File.open(ssl_file_path('localhost-server-key.pem')))
              new_context.ca_file = ssl_file_path('ca.pem')
            end
          else
            OpenSSL::SSL::SSLContext.new.tap do |new_context|
              new_context.cert = OpenSSL::X509::Certificate.new(File.open(ssl_file_path('no-sni.pem')))
              new_context.key = OpenSSL::PKey::RSA.new(File.open(ssl_file_path('no-sni-key.pem')))
              new_context.ca_file = ssl_file_path('ca.pem')
            end
          end
        }
      end
      tcp_server = OpenSSL::SSL::SSLServer.new(tcp_server, context)
    end

    self.server = tcp_server
    self.thread = Thread.new do
      begin
        loop do
          logger.debug 'Waiting for a client to connect'

          # Wait for a client to connect
          on_request(server.accept)
        end
      rescue IOError, Errno::EBADF => exc
        logger.info('Thread terminated', exc)
      end
    end
  end

  def stop
    if thread
      thread.kill
      thread.join
      self.thread = nil
    end
    begin
      server.close if server
    rescue IOError
    end
  end

  # Called for each message received from the client
  # Returns a Hash that is sent back to the caller
  def on_message(message)
    case message['action']
    when 'test1'
      {'result' => 'test1'}
    when 'servername'
      {'result' => @name}
    when 'sleep'
      sleep message['duration'] || 1
      {'result' => 'sleep'}
    when 'fail'
      if message['attempt'].to_i >= 2
        {'result' => 'fail'}
      else
        nil
      end
    else
      {'result' => "Unknown action: #{message['action']}"}
    end
  end

  # Called for each client connection
  # In a real server each request would be handled in a separate thread
  def on_request(client)
    logger.debug 'Client connected, waiting for data from client'

    while (request = read_bson_document(client)) do
      logger.debug 'Received request', request
      break unless request

      if reply = on_message(request)
        logger.debug 'Sending Reply'
        logger.trace 'Reply', reply
        client.print(reply.to_bson)
      else
        logger.debug 'Closing client since no reply is being sent back'
        server.close
        client.close
        logger.debug 'Server closed'
        start
        logger.debug 'Server Restarted'
        break
      end
    end
    # Disconnect from the client
    client.close
    logger.debug 'Disconnected from the client'
  end

end

if $0 == __FILE__
  SemanticLogger.default_level = :trace
  SemanticLogger.add_appender(STDOUT)
  server = SimpleTCPServer.new(port: 2000)

  # For SSL:
  # server = SimpleTCPServer.new(
  #   port: 2000,
  #   ssl:  {
  #     cert:    ssl_file_path('localhost-server.pem'),
  #     key:     ssl_file_path('localhost-server-key.pem'),
  #     ca_file: ssl_file_path('ca.pem')
  #   }
  # )

  server.thread.join
end
