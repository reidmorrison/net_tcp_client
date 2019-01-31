require 'socket'
require_relative 'test_helper'
require_relative 'simple_tcp_server'
require 'securerandom'

# Unit Test for Net::TCPClient
class TCPClientTest < Minitest::Test
  describe Net::TCPClient do
    [false, true].each do |with_ssl|
      describe (with_ssl ? 'with ssl' : 'without ssl') do
        describe '#connect' do
          it 'raises an exception when cannot reach server after 5 retries' do
            exception = assert_raises Net::TCPClient::ConnectionFailure do
              new_net_tcp_client(
                with_ssl,
                server:                 'localhost:3300',
                connect_retry_interval: 0.1,
                connect_retry_count:    5
              )
            end
            assert_match(/Connection failure connecting to/, exception.message)
            assert_match Errno::ECONNREFUSED.to_s, exception.cause.class.to_s
          end

          it 'times out on connect' do
            unless with_ssl
              skip('When not using SSL it will often connect anyway. Maybe a better way to test non-ssl?')
            end

            # Create a TCP Server, but do not respond to connections to cause a connect timeout
            server = TCPServer.open(2094)
            sleep 1

            exception = assert_raises Net::TCPClient::ConnectionTimeout do
              new_net_tcp_client(
                with_ssl,
                server:              'localhost:2094',
                connect_timeout:     0.5,
                connect_retry_count: 3
              )
            end
            assert_match(/Timed out after 0\.5 seconds/, exception.message)
            server.close
          end
        end

        describe 'with server' do
          before do
            @port   = 2000 + SecureRandom.random_number(1000)
            options = {port: @port}
            if with_ssl
              options[:ssl] = {
                # Purposefully serve a cert that doesn't match 'localhost' to force failures unless SNI works.
                cert:    OpenSSL::X509::Certificate.new(File.open(ssl_file_path('no-sni.pem'))),
                key:     OpenSSL::PKey::RSA.new(File.open(ssl_file_path('no-sni-key.pem'))),
                ca_file: ssl_file_path('ca.pem')
              }
            end
            count = 0
            begin
              @server = SimpleTCPServer.new(options)
            rescue Errno::EADDRINUSE => exc
              @server.stop if @server
              # Give previous test server time to stop
              count += 1
              sleep 1
              retry if count <= 30
              raise exc
            end

            @server_name = "localhost:#{@port}"
          end

          after do
            @client.close if @client
            @server.stop if @server
          end

          describe '#read' do
            it 'read timeout, followed by successful read' do
              @read_timeout = 3.0
              # Need a custom client that does not auto close on error:
              @client = new_net_tcp_client(
                with_ssl,
                server:         @server_name,
                read_timeout:   @read_timeout,
                close_on_error: false
              )

              request = {'action' => 'sleep', 'duration' => @read_timeout + 0.5}
              @client.write(request.to_bson)

              exception = assert_raises Net::TCPClient::ReadTimeout do
                # Read 4 bytes from server
                @client.read(4)
              end
              assert_equal false, @client.close_on_error
              assert @client.alive?, 'The client connection is not alive after the read timed out with close_on_error: false'
              assert_equal "Timed out after #{@read_timeout} seconds trying to read from localhost[127.0.0.1]:#{@port}", exception.message
              reply = read_bson_document(@client)
              assert_equal 'sleep', reply['result']
              @client.close
            end

            it 'infinite timeout' do
              @client = new_net_tcp_client(
                with_ssl,
                server:          @server_name,
                connect_timeout: -1
              )
              request = {'action' => 'test1'}
              @client.write(request.to_bson)
              reply = read_bson_document(@client)
              assert_equal 'test1', reply['result']
              @client.close
            end
          end

          describe '#connect' do
            it 'calls on_connect after connection' do
              @client = new_net_tcp_client(
                with_ssl,
                server:       @server_name,
                read_timeout: 3,
                on_connect:   Proc.new do |socket|
                  # Reset user_data on each connection
                  socket.user_data = {sequence: 1}
                end
              )
              assert_equal "localhost[127.0.0.1]:#{@port}", @client.address.to_s
              assert_equal 1, @client.user_data[:sequence]

              request = {'action' => 'test1'}
              @client.write(request.to_bson)
              reply = read_bson_document(@client)
              assert_equal 'test1', reply['result']
            end
          end

          describe 'failover' do
            it 'connects to second server when the first is down' do
              @client = new_net_tcp_client(
                with_ssl,
                servers:      ['localhost:1999', @server_name],
                read_timeout: 3
              )
              assert_equal "localhost[127.0.0.1]:#{@port}", @client.address.to_s

              request = {'action' => 'test1'}
              @client.write(request.to_bson)
              reply = read_bson_document(@client)
              assert_equal 'test1', reply['result']
            end
          end

          describe 'with client' do
            before do
              @read_timeout = 3.0
              @client       = new_net_tcp_client(
                with_ssl,
                server:       @server_name,
                read_timeout: @read_timeout
              )
              assert @client.alive?, @client.ai
              assert_equal true, @client.close_on_error
            end

            describe '#alive?' do
              it 'returns false once the connection is closed' do
                skip "TODO: #alive? hangs with the latest SSL changes" if with_ssl
                assert @client.alive?
                @client.close
                refute @client.alive?
              end
            end

            describe '#closed?' do
              it 'returns true once the connection is closed' do
                refute @client.closed?
                @client.close
                assert @client.closed?
              end
            end

            describe '#close' do
              it 'closes the connection, repeatedly without error' do
                @client.close
                @client.close
              end
            end

            describe '#write' do
              it 'writes data' do
                request = {'action' => 'test1'}
                @client.write(request.to_bson)
              end
            end

            describe '#read' do
              it 'reads a response' do
                request = {'action' => 'test1'}
                @client.write(request.to_bson)
                reply = read_bson_document(@client)
                assert_equal 'test1', reply['result']
              end

              it 'times out on receive' do
                request = {'action' => 'sleep', 'duration' => @read_timeout + 0.5}
                @client.write(request.to_bson)

                exception = assert_raises Net::TCPClient::ReadTimeout do
                  # Read 4 bytes from server
                  @client.read(4)
                end
                # Due to close_on_error: true, a timeout will close the connection
                # to prevent use of a socket connection in an inconsistent state
                assert_equal false, @client.alive?
                assert_equal "Timed out after #{@read_timeout} seconds trying to read from localhost[127.0.0.1]:#{@port}", exception.message
              end
            end

            describe '#retry_on_connection_failure' do
              it 'retries on connection failure' do
                attempt = 0
                reply   = @client.retry_on_connection_failure do
                  request = {'action' => 'fail', 'attempt' => (attempt += 1)}
                  @client.write(request.to_bson)
                  read_bson_document(@client)
                end
                assert_equal 'fail', reply['result']
              end
            end
          end
        end
      end

    end

    def ssl_file_path(name)
      File.join(File.dirname(__FILE__), 'ssl_files', name)
    end

    def new_net_tcp_client(with_ssl, params)
      params = params.dup
      if with_ssl
        params.merge!(
          ssl: {
            ca_file:     ssl_file_path('ca.pem'),
            verify_mode: OpenSSL::SSL::VERIFY_PEER
          }
        )
      end
      Net::TCPClient.new(params)
    end

  end
end
