require 'socket'
require_relative 'test_helper'
require_relative 'simple_tcp_server'

# Unit Test for Net::TCPClient
class TCPClientTest < Minitest::Test
  describe Net::TCPClient do
    before do
      unless defined?(SemanticLogger)
        require 'logger'
        @logger       = Logger.new('test.log')
        @logger.level = Logger::DEBUG
      end
    end

    describe 'without server' do
      it 'raises an exception when cannot reach server after 5 retries' do
        exception = assert_raises Net::TCPClient::ConnectionFailure do
          Net::TCPClient.new(
            server:                 'localhost:3300',
            connect_retry_interval: 0.1,
            connect_retry_count:    5,
            logger:                 @logger
          )
        end
        assert_match /Failed to connect to any of localhost:3300 after 5 retries/, exception.message
        assert_match Errno::ECONNREFUSED.to_s, exception.cause.class.to_s
      end

      it 'times out on connect' do
        # Create a TCP Server, but do not respond to connections
        server = TCPServer.open(2001)

        exception = assert_raises Net::TCPClient::ConnectionFailure do
          1000.times do
            Net::TCPClient.new(
              server:              'localhost:2001',
              connect_timeout:     0.5,
              connect_retry_count: 3,
              logger:              @logger
            )
          end
        end
        assert_match /Failed to connect to any of localhost:2001 after 3 retries/, exception.message
        server.close
      end

    end

    describe "with server" do
      before do
        @server      = SimpleTCPServer.new(2000, @logger)
        @server_name = 'localhost:2000'
      end

      after do
        @server.stop if @server
      end

      describe 'without client connection' do
        it 'times out on first receive and then successfully reads the response' do
          @read_timeout = 3.0
          # Need a custom client that does not auto close on error:
          @client       = Net::TCPClient.new(
            server:         @server_name,
            read_timeout:   @read_timeout,
            close_on_error: false,
            logger:         @logger
          )

          request = {'action' => 'sleep', 'duration' => @read_timeout + 0.5}
          @client.write(BSON.serialize(request))

          exception = assert_raises Net::TCPClient::ReadTimeout do
            # Read 4 bytes from server
            @client.read(4)
          end
          assert_equal false, @client.close_on_error
          assert @client.alive?, 'The client connection is not alive after the read timed out with close_on_error: false'
          assert_equal "Timedout after #{@read_timeout} seconds trying to read from localhost[127.0.0.1]:2000", exception.message
          reply = read_bson_document(@client)
          assert_equal 'sleep', reply['result']
          @client.close
        end

        it 'support infinite timeout' do
          @client = Net::TCPClient.new(
            server:          @server_name,
            connect_timeout: -1,
            logger:          @logger
          )
          request = {'action' => 'test1'}
          @client.write(BSON.serialize(request))
          reply = read_bson_document(@client)
          assert_equal 'test1', reply['result']
          @client.close
        end
      end

      describe 'with client connection' do
        before do
          @read_timeout = 3.0
          @client       = Net::TCPClient.new(
            server:       @server_name,
            read_timeout: @read_timeout,
            logger:       @logger
          )
          assert @client.alive?
          assert_equal true, @client.close_on_error
        end

        def after
          if @client
            @client.close
            assert !@client.alive?
          end
        end

        it 'sends and receives data' do
          request = {'action' => 'test1'}
          @client.write(BSON.serialize(request))
          reply = read_bson_document(@client)
          assert_equal 'test1', reply['result']
        end

        it 'timeouts on receive' do
          request = {'action' => 'sleep', 'duration' => @read_timeout + 0.5}
          @client.write(BSON.serialize(request))

          exception = assert_raises Net::TCPClient::ReadTimeout do
            # Read 4 bytes from server
            @client.read(4)
          end
          # Due to close_on_error: true, a timeout will close the connection
          # to prevent use of a socket connection in an inconsistent state
          assert_equal false, @client.alive?
          assert_equal "Timedout after #{@read_timeout} seconds trying to read from localhost[127.0.0.1]:2000", exception.message
        end

        it 'retries on connection failure' do
          attempt = 0
          reply   = @client.retry_on_connection_failure do
            request = {'action' => 'fail', 'attempt' => (attempt+=1)}
            @client.write(BSON.serialize(request))
            # Note: Do not put the read in this block if it never sends the
            #       same request twice to the server
            read_bson_document(@client)
          end
          assert_equal 'fail', reply['result']
        end

      end

      describe 'without client connection' do
        it 'connects to second server when the first is down' do
          client = Net::TCPClient.new(
            servers:      ['localhost:1999', @server_name],
            read_timeout: 3,
            logger:       @logger
          )
          assert_equal 'localhost[127.0.0.1]:2000', client.server

          request = {'action' => 'test1'}
          client.write(BSON.serialize(request))
          reply = read_bson_document(client)
          assert_equal 'test1', reply['result']

          client.close
        end

        it 'calls on_connect after connection' do
          client = Net::TCPClient.new(
            server:       @server_name,
            read_timeout: 3,
            on_connect:   Proc.new do |socket|
              # Reset user_data on each connection
              socket.user_data = {sequence: 1}
            end,
            logger:       @logger
          )
          assert_equal 'localhost[127.0.0.1]:2000', client.server
          assert_equal 1, client.user_data[:sequence]

          request = {'action' => 'test1'}
          client.write(BSON.serialize(request))
          reply = read_bson_document(client)
          assert_equal 'test1', reply['result']

          client.close
        end
      end

    end

  end
end
