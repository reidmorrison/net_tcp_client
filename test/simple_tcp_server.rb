require 'socket'
require 'bson'
require 'logger'

# Read the bson document, returning nil if the IO is closed
# before receiving any data or a complete BSON document
def read_bson_document(io)
  bytebuf = BSON::ByteBuffer.new
  # Read 4 byte size of following BSON document
  bytes   = io.read(4)
  return unless bytes
  # Read BSON document
  sz = bytes.unpack("V")[0]
  bytebuf.append!(bytes)
  bytes = io.read(sz-4)
  return unless bytes
  bytebuf.append!(bytes)
  return BSON.deserialize(bytebuf)
end

# Simple single threaded server for testing purposes using a local socket
# Sends and receives BSON Messages
class SimpleTCPServer
  attr_accessor :thread, :server, :logger

  def initialize(port = 2000, logger = nil)
    @logger = defined?(SemanticLogger::Logger) ? SemanticLogger[self.class] : logger
    start(port)
  end

  def start(port)
    self.server = TCPServer.open(port)
    self.thread = Thread.new do
      loop do
        logger.debug 'Waiting for a client to connect'

        # Wait for a client to connect
        on_request(server.accept)
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
      logger.debug "Received request: #{request.inspect}"
      break unless request

      if reply = on_message(request)
        logger.debug 'Sending Reply'
        logger.debug "Reply: #{reply.inspect}"
        client.print(BSON.serialize(reply))
      else
        logger.debug 'Closing client since no reply is being sent back'
        server.close
        client.close
        logger.debug 'Server closed'
        start(2000)
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
  server = SimpleTCPServer.new(2000)
  server.thread.join
end
