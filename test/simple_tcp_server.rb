require "socket"
require "openssl"
require "json"
require "semantic_logger"

# The messages that the tests and SimpleTCPServer exchange: a Hash as JSON, after its size in
# bytes as a 4 byte unsigned integer.
module Message
  # Returns [String] the supplied Hash as a message
  def self.dump(hash)
    json = JSON.generate(hash)
    [json.bytesize].pack("N") + json
  end

  # Returns [Hash] the next message read from the supplied IO, or nil if the IO is closed
  # before a complete message arrives
  def self.read(io)
    header = io.read(4)
    return unless header&.bytesize == 4

    size = header.unpack1("N")
    json = io.read(size)
    return unless json&.bytesize == size

    JSON.parse(json)
  end
end

def ssl_file_path(name)
  File.join(File.dirname(__FILE__), "ssl_files", name)
end

# Simple single threaded server for testing purposes using a local socket
# Sends and receives Messages
class SimpleTCPServer
  include SemanticLogger::Loggable
  attr_accessor :thread, :server
  attr_reader :port, :name, :ssl

  def initialize(options = {})
    @port = (options[:port] || 2000).to_i
    @name = options[:name] || "tcp"
    @ssl  = options[:ssl] || false
    start
  end

  def start
    # Only IPv4, so that a client of "localhost" that cannot connect over IPv4 fails instead of
    # falling back to IPv6.
    tcp_server = TCPServer.open("127.0.0.1", port)

    if ssl
      context = OpenSSL::SSL::SSLContext.new.tap do |context|
        context.set_params(ssl)
        context.servername_cb = proc { |_socket, name|
          if name == "localhost"
            OpenSSL::SSL::SSLContext.new.tap do |new_context|
              new_context.cert = OpenSSL::X509::Certificate.new(File.open(ssl_file_path("localhost-server.pem")))
              new_context.key = OpenSSL::PKey::RSA.new(File.open(ssl_file_path("localhost-server-key.pem")))
              new_context.ca_file = ssl_file_path("ca.pem")
            end
          else
            OpenSSL::SSL::SSLContext.new.tap do |new_context|
              new_context.cert = OpenSSL::X509::Certificate.new(File.open(ssl_file_path("no-sni.pem")))
              new_context.key = OpenSSL::PKey::RSA.new(File.open(ssl_file_path("no-sni-key.pem")))
              new_context.ca_file = ssl_file_path("ca.pem")
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
          logger.debug "Waiting for a client to connect"

          # Wait for a client to connect
          begin
            on_request(server.accept)
          rescue IOError, SystemCallError, OpenSSL::SSL::SSLError => e
            # Once the server is closed, end the thread without an exception: #stop closes the
            # server while this thread may be reading from a client, and Thread#join in #stop
            # would raise the exception that ended the thread in the test that stops the server.
            if server.closed?
              logger.info("Server closed, stopping", e)
              break
            end

            # One failed client, such as a failed SSL handshake or a reset connection, must not
            # stop the server: its listening socket would stay open, and every later client would
            # connect and then wait for a reply that never comes.
            logger.warn("Client connection failed", e)
          end
        end
      rescue IOError, Errno::EBADF => e
        logger.info("Thread terminated", e)
      end
    end
  end

  def stop
    # Close the server first: on JRuby, Thread#kill does not interrupt a thread that is waiting
    # in accept, but closing the server it is waiting on does.
    begin
      server&.close
    rescue IOError
    end
    return unless thread

    thread.kill
    thread.join(5)
    self.thread = nil
  end

  # Called for each message received from the client
  # Returns a Hash that is sent back to the caller
  def on_message(message)
    case message["action"]
    when "test1"
      {"result" => "test1"}
    when "servername"
      {"result" => @name}
    when "sleep"
      sleep message["duration"] || 1
      {"result" => "sleep"}
    when "fail"
      {"result" => "fail"} if message["attempt"].to_i >= 2
    else
      {"result" => "Unknown action: #{message['action']}"}
    end
  end

  # Called for each client connection
  # In a real server each request would be handled in a separate thread
  def on_request(client)
    logger.debug "Client connected, waiting for data from client"

    while (request = Message.read(client))
      logger.debug "Received request", request
      break unless request

      if (reply = on_message(request))
        logger.debug "Sending Reply"
        logger.trace "Reply", reply
        client.print(Message.dump(reply))
      else
        logger.debug "Closing client since no reply is being sent back"
        server.close
        client.close
        logger.debug "Server closed"
        start
        logger.debug "Server Restarted"
        break
      end
    end
    # Disconnect from the client
    client.close
    logger.debug "Disconnected from the client"
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
