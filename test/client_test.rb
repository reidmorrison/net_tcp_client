require 'socket'
require_relative 'test_helper'
require_relative 'simple_tcp_server'
require_relative 'simple_ssl_server'

def create_client(klass, params={})
  params = params.dup
  if klass == Net::SSLClient
    params.merge!(
      ssl_context_params: {
        ca_file: ssl_file_path('ca.pem')
      })
  end
  klass.new(params)
end

# Unit Test for Net::TCPClient and Net::SSLClient
module Net
  class ClientTest < Minitest::Test
    [ TCPClient, SSLClient ].each do |klass|
      describe klass do
        describe 'without server' do
          it 'raises an exception when cannot reach server after 5 retries' do
            exception = assert_raises TCPClient::ConnectionFailure do
              create_client(klass,
                server:                 'localhost:3300',
                connect_retry_interval: 0.1,
                connect_retry_count:    5)
            end
            assert_match /After 5 connection attempts to host 'localhost:3300': Errno::ECONNREFUSED/, exception.message
          end

          it 'times out on connect' do
            # Create a TCP Server, but do not respond to connections
            server = TCPServer.open(2001)

            exception = assert_raises TCPClient::ConnectionTimeout do
              1000.times do
                create_client(klass,
                  server:              'localhost:2001',
                  connect_timeout:     0.5,
                  connect_retry_count: 3
                )
              end
            end
            assert_match /Timedout after/, exception.message
            server.close
          end

        end

        describe "with server" do
          before do
            @server      =
              if klass == TCPClient
                SimpleTCPServer.new(2000)
              else
                SimpleSSLServer.new(
                  2000,
                  ssl_file_path('localhost-server.pem'),
                  ssl_file_path('localhost-server-key.pem'),
                  ssl_file_path('ca.pem'))
              end
            @server_name = 'localhost:2000'
          end

          after do
            @server.stop if @server
          end

          describe 'without client connection' do
            it 'times out on first receive and then successfully reads the response' do
              @read_timeout = 3.0
              # Need a custom client that does not auto close on error:
              @client       = create_client(klass,
                server:         @server_name,
                read_timeout:   @read_timeout,
                close_on_error: false
              )

              request = {'action' => 'sleep', 'duration' => @read_timeout + 0.5}
              @client.write(BSON.serialize(request))

              exception = assert_raises TCPClient::ReadTimeout do
                # Read 4 bytes from server
                @client.read(4)
              end
              assert_equal false, @client.close_on_error
              assert @client.alive?, 'The client connection is not alive after the read timed out with close_on_error: false'
              assert_match /Timedout after #{@read_timeout} seconds trying to read from #{@server_name}/, exception.message
              reply = read_bson_document(@client)
              assert_equal 'sleep', reply['result']
              @client.close
            end

            it 'support infinite timeout' do
              @client = create_client(klass,
                server:          @server_name,
                connect_timeout: -1
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
              @client       = create_client(klass,
                server:       @server_name,
                read_timeout: @read_timeout
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

              exception = assert_raises TCPClient::ReadTimeout do
                # Read 4 bytes from server
                @client.read(4)
              end
              # Due to close_on_error: true, a timeout will close the connection
              # to prevent use of a socket connection in an inconsistent state
              assert_equal false, @client.alive?
              assert_match /Timedout after #{@read_timeout} seconds trying to read from #{@server_name}/, exception.message
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
              client = create_client(klass,
                servers:      ['localhost:1999', @server_name],
                read_timeout: 3
              )
              assert_equal @server_name, client.server

              request = {'action' => 'test1'}
              client.write(BSON.serialize(request))
              reply = read_bson_document(client)
              assert_equal 'test1', reply['result']

              client.close
            end

            it 'calls on_connect after connection' do
              client = create_client(klass,
                server:       @server_name,
                read_timeout: 3,
                on_connect:   Proc.new do |socket|
                  # Reset user_data on each connection
                  socket.user_data = {sequence: 1}
                end
              )
              assert_equal @server_name, client.server
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
  end
end
