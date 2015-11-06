require 'openssl'

module Net
  class SSLClient
    [:read_timeout, :connect_timeout, :connect_retry_count,
     :retry_count, :connect_retry_interval, :server_selector, :close_on_error,
     :user_data].each do |field|
      define_method(:"#{field}") do
        @tcp_client.send(:"#{field}")
      end
      define_method(:"#{field}=") do |v|
        @tcp_client.send(:"#{field}=", v)
      end
    end

    [:buffered, :server, :logger].each do |field|
      define_method(:"#{field}") do
        @tcp_client.send(:"#{field}")
      end
    end

    attr_accessor :ssl_connect_timeout, :write_timeout, :ssl_context_params,
                  :ssl_connect_retry_count, :ssl_connect_retry_interval

    def self.connect(params={})
      begin
        connection = self.new(params)
        yield(connection)
      ensure
        connection.close if connection
      end
    end

    def initialize(parameters={})
      params                      = parameters.dup
      @write_timeout              = (params[:write_timeout] || 60.0).to_f
      @ssl_connect_timeout        = (params.delete(:ssl_connect_timeout) || 30.0).to_f
      @ssl_context_params         = (params.delete(:ssl_context_params) || {})
      @ssl_connect_retry_count    = params.delete(:ssl_connect_retry_count) || 10
      @ssl_connect_retry_interval = (params.delete(:ssl_connect_retry_interval) || 0.5).to_f
      on_connect                  = params.delete(:on_connect)
      params.merge!(on_tcp_connect: method(:connect_ssl))
      params.merge!(on_connect: Proc.new { on_connect.call(self) }) if on_connect
      @tcp_client                 = TCPClient.new(params)
    end

    def connect
      @tcp_client.connect if closed?
      true
    end

    def write(data, timeout = write_timeout)
      data = data.to_s
      logger.trace('SSL#write ==> sending', data)
      stats = {}
      logger.benchmark_debug('SSL#write ==> complete', stats) do
        begin
          deadline = Time.now.utc + timeout
          stats[:bytes_sent] =
            nonblock_with_deadline(@ssl_socket, deadline) do
              @ssl_socket.write_nonblock(data)
            end
        rescue SslTimedOut
          close if close_on_error
          logger.warn "#write Timeout after #{timeout} seconds"
          raise Net::TCPClient::WriteTimeout.new("Timedout after #{timeout} seconds trying to read from #{server}")
        rescue SystemCallError => exception
          logger.warn "#write Connection failure: #{exception.class}: #{exception.message}"
          close if close_on_error
          raise Net::TCPClient::ConnectionFailure.new("Send Connection failure: #{exception.class}: #{exception.message}", server, exception)
        rescue Exception
          # Close the connection on any other exception since the connection
          # will now be in an inconsistent state
          close if close_on_error
          raise
        end
      end
    end

    def read(length, buffer = nil, timeout = read_timeout)
      result = nil
      logger.benchmark_debug("SSL#read <== read #{length} bytes") do
        # Read data from socket
        begin
          deadline = Time.now.utc + timeout
          result =
            nonblock_with_deadline(@ssl_socket, deadline) do
              buffer.nil? ? @ssl_socket.read_nonblock(length) : @ssl_socket.read_nonblock(length, buffer)
            end

          logger.trace('SSL#read <== received', result)

          # EOF before all the data was returned
          if result.nil? || (result.length < length)
            close if close_on_error
            logger.warn "SSL#read server closed the connection before #{length} bytes were returned"
            raise Net::TCPClient::ConnectionFailure.new('Connection lost while reading data', server, EOFError.new('end of file reached'))
          end
        rescue SystemCallError, IOError => exception
          close if close_on_error
          logger.warn "SSL#read Connection failure while reading data: #{exception.class}: #{exception.message}"
          raise Net::TCPClient::ConnectionFailure.new("#{exception.class}: #{exception.message}", server, exception)
        rescue SslTimedOut
          close if close_on_error
          logger.warn "SSL#read Timeout after #{timeout} seconds"
          raise Net::TCPClient::ReadTimeout.new("Timedout after #{timeout} seconds trying to read from #{server}")
        rescue Exception
          # Close the connection on any other exception since the connection
          # will now be in an inconsistent state
          close if close_on_error
          raise
        end
      end
      result
    end

    def retry_on_connection_failure
      @tcp_client.retry_on_connection_failure do |_tcp_client|
        yield(self)
      end
    end

    # Close the socket only if it is not already closed
    #
    # Logs a warning if an error occurs trying to close the socket
    def close
      @ssl_socket.close unless @ssl_socket.closed?
      @tcp_client.close unless @tcp_client.closed?
    rescue IOError => exception
      logger.warn "IOError when attempting to close socket: #{exception.class}: #{exception.message}"
    end

    # Returns whether the socket is closed
    def closed?
      @ssl_socket.closed? || @tcp_client.closed?
    end

    def alive?
      !closed?
    end

    #############################################
    protected

    SslTimedOut = Class.new(StandardError)

    # Try connecting to a single server
    # Returns the connected socket
    #
    # Raises Net::TCPClient::ConnectionTimeout when the connection timeout has been exceeded
    # Raises Net::TCPClient::ConnectionFailure
    def connect_ssl(tcp_client, socket, server)
      @tcp_client ||= tcp_client

      retries = 0
      logger.benchmark_info "SSL Connection to #{@tcp_client.server}" do
        context = OpenSSL::SSL::SSLContext.new
        context.set_params(@ssl_context_params)
        @ssl_socket = OpenSSL::SSL::SSLSocket.new(socket, context)

        begin
          if @ssl_connect_timeout == -1
            # Timeout of -1 means wait forever for a connection
            @ssl_socket.connect
          else
            deadline = Time.now.utc + @ssl_connect_timeout
            begin
              nonblock_with_deadline(@ssl_socket, deadline) do
                @ssl_socket.connect_nonblock
              end
            rescue Errno::EISCONN
              # Our connection was successful.
            rescue SslTimedOut
              close
              raise Net::TCPClient::ConnectionTimeout.new(
                      "SSL Timedout after #{@ssl_connect_timeout} seconds trying to connect to #{server}")
            end
          end

          unless OpenSSL::SSL.verify_certificate_identity(
            @ssl_socket.peer_cert,
            server.split(':', 2)[0])
            close
            raise Net::TCPClient::ConnectionFailure.new(
                    'SSL handshake failed due to a hostname mismatch.', server)
          end
        rescue OpenSSL::SSL::SSLError => exception
          close
          logger.warn "SSL handshake failure: #{exception.class}: #{exception.message}. Retry: #{retries}"
          raise Net::TCPClient::ConnectionFailure.new(
                  "SSL handshake to #{server} failed due to a ssl error #{exception.class}: #{exception.message}",
                  server)
        rescue SystemCallError => exception
          close
          if retries < @ssl_connect_retry_count && self.class.reconnect_on_errors.include?(exception.class)
            retries += 1
            logger.warn "SSL handshake failure: #{exception.class}: #{exception.message}. Retry: #{retries}"
            sleep @ssl_connect_retry_interval
            retry
          end
          logger.error "SSL handshake failure: #{exception.class}: #{exception.message}. Giving up after #{retries} retries"
          raise Net::TCPClient::ConnectionFailure.new(
                  "After #{retries} ssl handshake attempts to host '#{server}': #{exception.class}: #{exception.message}", server, exception)
        end
      end
    end

    def nonblock_with_deadline(socket, deadline)
      yield
    rescue IO::WaitWritable, IO::WaitReadable => e
      (readable, writable) =
        if e == IO::WaitReadable
          [[socket], nil]
        else
          [nil, [socket]]
        end

      time_remaining = deadline - Time.now.utc
      if time_remaining > 0 &&
        IO.select(readable, writable, nil, time_remaining)
        retry
      else
        raise SslTimedOut
      end
    end
  end
end
