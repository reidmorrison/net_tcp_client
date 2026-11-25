require "socket"
require_relative "test_helper"
require_relative "simple_tcp_server"
require "securerandom"

# Unit Test for Net::TCPClient
class TCPClientTest < Minitest::Test
  # A server in TEST-NET-1 (RFC 5737): packets to it are dropped, so connecting to it times out.
  UNROUTED_SERVER = "192.0.2.1:80".freeze

  describe Net::TCPClient do
    [false, true].each do |with_ssl|
      describe(with_ssl ? "with ssl" : "without ssl") do
        describe "#connect" do
          it "raises an exception when cannot reach server after 5 retries" do
            exception = assert_raises Net::TCPClient::ConnectionFailure do
              new_net_tcp_client(
                with_ssl,
                server:                 "localhost:3300",
                connect_retry_interval: 0.1,
                connect_retry_count:    5
              )
            end
            assert_match(/Connection failure connecting to/, exception.message)
            assert_match Errno::ECONNREFUSED.to_s, exception.cause.class.to_s
          end

          it "times out on connect" do
            # With SSL, a server that accepts connections but never answers times out the SSL handshake.
            # Without SSL, the TCP connect itself must time out: a listening server would complete it, so
            # connect instead to an address in TEST-NET-1 (RFC 5737), which is never routed.
            server      = TCPServer.new("127.0.0.1", 0) if with_ssl
            server_name = with_ssl ? "127.0.0.1:#{server.addr[1]}" : UNROUTED_SERVER

            exception = assert_raises Net::TCPClient::ConnectionTimeout do
              new_net_tcp_client(
                with_ssl,
                server:              server_name,
                connect_timeout:     0.5,
                connect_retry_count: 3
              )
            rescue Net::TCPClient::ConnectionFailure => e
              raise if with_ssl

              # The network rejected the connection at once, instead of dropping it
              skip "Connecting to #{UNROUTED_SERVER} fails at once with #{e.cause.class}, so it cannot time out here"
            end
            assert_match(/Timed out after 0\.5 seconds/, exception.message)
          ensure
            server&.close
          end
        end

        describe "with server" do
          before do
            @port   = 2000 + SecureRandom.random_number(1000)
            options = {port: @port}
            if with_ssl
              options[:ssl] = {
                # Purposefully serve a cert that doesn't match 'localhost' to force failures unless SNI works.
                cert:    OpenSSL::X509::Certificate.new(File.open(ssl_file_path("no-sni.pem"))),
                key:     OpenSSL::PKey::RSA.new(File.open(ssl_file_path("no-sni-key.pem"))),
                ca_file: ssl_file_path("ca.pem")
              }
            end
            count = 0
            begin
              @server = SimpleTCPServer.new(options)
            rescue Errno::EADDRINUSE => e
              @server&.stop
              # Give previous test server time to stop
              count += 1
              sleep 1
              retry if count <= 30
              raise e
            end

            @server_name = "localhost:#{@port}"
          end

          after do
            @client&.close
            @server&.stop
          end

          describe "#read" do
            it "read timeout, followed by successful read" do
              @read_timeout = 3.0
              # Need a custom client that does not auto close on error:
              @client = new_net_tcp_client(
                with_ssl,
                server:         @server_name,
                read_timeout:   @read_timeout,
                close_on_error: false
              )

              request = {"action" => "sleep", "duration" => @read_timeout + 0.5}
              @client.write(request.to_bson)

              exception = assert_raises Net::TCPClient::ReadTimeout do
                # Read 4 bytes from server
                @client.read(4)
              end
              assert_equal false, @client.close_on_error
              assert @client.alive?, "The client connection is not alive after the read timed out with close_on_error: false"
              assert_equal "Timed out after #{@read_timeout} seconds trying to read from localhost[127.0.0.1]:#{@port}", exception.message
              reply = read_bson_document(@client)
              assert_equal "sleep", reply["result"]
              @client.close
            end

            it "infinite timeout" do
              @client = new_net_tcp_client(
                with_ssl,
                server:          @server_name,
                connect_timeout: -1
              )
              request = {"action" => "test1"}
              @client.write(request.to_bson)
              reply = read_bson_document(@client)
              assert_equal "test1", reply["result"]
              @client.close
            end
          end

          describe "#connect" do
            it "calls on_connect after connection" do
              @client = new_net_tcp_client(
                with_ssl,
                server:       @server_name,
                read_timeout: 3,
                on_connect:   proc do |socket|
                  # Reset user_data on each connection
                  socket.user_data = {sequence: 1}
                end
              )
              assert_equal "localhost[127.0.0.1]:#{@port}", @client.address.to_s
              assert_equal 1, @client.user_data[:sequence]

              request = {"action" => "test1"}
              @client.write(request.to_bson)
              reply = read_bson_document(@client)
              assert_equal "test1", reply["result"]
            end
          end

          describe "failover" do
            it "connects to second server when the first is down" do
              @client = new_net_tcp_client(
                with_ssl,
                servers:      ["localhost:1999", @server_name],
                read_timeout: 3
              )
              assert_equal "localhost[127.0.0.1]:#{@port}", @client.address.to_s

              request = {"action" => "test1"}
              @client.write(request.to_bson)
              reply = read_bson_document(@client)
              assert_equal "test1", reply["result"]
            end
          end

          describe "with client" do
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

            describe "#alive?" do
              it "returns false once the connection is closed" do
                assert @client.alive?
                @client.close
                refute @client.alive?
              end

              it "returns false once the server closes the connection" do
                # The server closes the connection, without a reply, on the first attempt
                @client.write({"action" => "fail", "attempt" => 1}.to_bson)
                deadline = Time.now + 5
                sleep 0.05 while @client.alive? && Time.now < deadline
                refute @client.alive?
              end

              it "keeps a reply that is waiting, for the next read" do
                @client.write({"action" => "test1"}.to_bson)
                sleep 0.05 until IO.select([@client.socket], nil, nil, 0)
                assert @client.alive?
                reply = read_bson_document(@client)
                assert_equal "test1", reply["result"]
              end
            end

            describe "#closed?" do
              it "returns true once the connection is closed" do
                refute @client.closed?
                @client.close
                assert @client.closed?
              end
            end

            describe "#close" do
              it "closes the connection, repeatedly without error" do
                @client.close
                @client.close
              end
            end

            describe "#write" do
              it "writes data" do
                request = {"action" => "test1"}
                @client.write(request.to_bson)
              end
            end

            describe "#read" do
              it "reads a response" do
                request = {"action" => "test1"}
                @client.write(request.to_bson)
                reply = read_bson_document(@client)
                assert_equal "test1", reply["result"]
              end

              it "times out on receive" do
                request = {"action" => "sleep", "duration" => @read_timeout + 0.5}
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

            describe "#retry_on_connection_failure" do
              it "retries on connection failure" do
                attempt = 0
                reply   = @client.retry_on_connection_failure do
                  request = {"action" => "fail", "attempt" => (attempt += 1)}
                  @client.write(request.to_bson)
                  read_bson_document(@client)
                end
                assert_equal "fail", reply["result"]
              end
            end
          end
        end
      end
    end

    describe "listening server" do
      after do
        @server&.close
      end

      describe ".connect" do
        before do
          @server = TCPServer.new("127.0.0.1", 0)
          @params = {server: "127.0.0.1:#{@server.addr[1]}", connect_retry_count: 0}
        end

        # https://github.com/reidmorrison/net_tcp_client/issues/21
        it "accepts a Hash of parameters" do
          address = Net::TCPClient.connect(@params) { |client| client.address.to_s }
          assert_equal "127.0.0.1[127.0.0.1]:#{@server.addr[1]}", address
        end

        it "accepts keyword arguments" do
          address = Net::TCPClient.connect(**@params) { |client| client.address.to_s }
          assert_equal "127.0.0.1[127.0.0.1]:#{@server.addr[1]}", address
        end

        it "closes the connection after the block" do
          client = Net::TCPClient.connect(@params) { |c| c }
          assert client.closed?
        end
      end

      describe "#read" do
        before do
          @server   = TCPServer.new("127.0.0.1", 0)
          @client   = Net::TCPClient.new(server: "127.0.0.1:#{@server.addr[1]}", connect_retry_count: 0, close_on_error: false)
          @accepted = @server.accept
        end

        after do
          @accepted&.close
          @client&.close
        end

        it "waits for data that arrives in pieces" do
          writer = Thread.new do
            @accepted.write("hel")
            sleep 0.2
            @accepted.write("lo")
          end
          assert_equal "hello", @client.read(5)
          writer.join
        end

        it "returns the data read before a timeout on the next read" do
          @accepted.write("hel")
          assert_raises(Net::TCPClient::ReadTimeout) { @client.read(5, nil, 0.2) }
          @accepted.write("lo")
          assert_equal "hello", @client.read(5)
        end

        it "fills the supplied buffer" do
          @accepted.write("hello")
          buffer = +"old contents"
          assert_same buffer, @client.read(5, buffer)
          assert_equal "hello", buffer
        end

        it "raises ConnectionFailure when the server closes the connection before all the data arrives" do
          @accepted.write("hel")
          @accepted.close
          exception = assert_raises(Net::TCPClient::ConnectionFailure) { @client.read(5) }
          assert_kind_of EOFError, exception.cause
        end
      end

      describe "IPv6" do
        before do
          begin
            @server = TCPServer.new("::1", 0)
          rescue SystemCallError => e
            skip "IPv6 loopback is not available: #{e.class}: #{e.message}"
          end
          @port = @server.addr[1]
        end

        it "connects to an IPv6 address" do
          @client = Net::TCPClient.new(server: "[::1]:#{@port}", connect_retry_count: 0)
          assert_equal "::1[::1]:#{@port}", @client.address.to_s
          accepted = @server.accept
          @client.write("hello")
          assert_equal "hello", accepted.read(5)
          accepted.write("world")
          assert_equal "world", @client.read(5)
        ensure
          accepted&.close
          @client&.close
        end

        it "falls back to the IPv6 address of a host name with no IPv4 server listening" do
          skip "localhost has no IPv6 address" unless Net::TCPClient::Address.ip_addresses("localhost").include?("::1")
          @client = Net::TCPClient.new(server: "localhost:#{@port}", connect_retry_count: 0)
          assert_equal "localhost[::1]:#{@port}", @client.address.to_s
        ensure
          @client&.close
        end
      end
    end

    describe "connect failure" do
      before do
        # A port that nothing listens on
        server = TCPServer.new("127.0.0.1", 0)
        @port  = server.addr[1]
        server.close
      end

      [:trace, :fatal].each do |level|
        it "raises the original exception when the log level is #{level}" do
          previous                     = Net::TCPClient.logger.level
          Net::TCPClient.logger.level  = level
          exception                    = assert_raises Net::TCPClient::ConnectionFailure do
            Net::TCPClient.new(server: "127.0.0.1:#{@port}", connect_retry_count: 0)
          end
          # The exception from connecting to the server, not one that wraps it
          assert_match(/\A#connect Connection failure connecting to/, exception.message)
          assert_kind_of Errno::ECONNREFUSED, exception.cause
        ensure
          Net::TCPClient.logger.level = previous
        end
      end
    end

    describe "proxy_server:" do
      it "is not supported" do
        exception = assert_raises ArgumentError do
          Net::TCPClient.new(server: "localhost:2000", proxy_server: "proxy:1080")
        end
        assert_match(/proxy_server: is not supported/, exception.message)
      end
    end

    def ssl_file_path(name)
      File.join(File.dirname(__FILE__), "ssl_files", name)
    end

    def new_net_tcp_client(with_ssl, params)
      params = params.dup
      if with_ssl
        params.merge!(
          ssl: {
            ca_file:     ssl_file_path("ca.pem"),
            verify_mode: OpenSSL::SSL::VERIFY_PEER
          }
        )
      end
      Net::TCPClient.new(**params)
    end
  end
end
