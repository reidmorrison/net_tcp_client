module Net
  class TCPClient
    # Add read, write and connect timeouts
    class Socket < ::Socket
      include SemanticLogger::Loggable if defined?(SemanticLogger::Loggable)

      attr_accessor :address, :buffered

      # Host name, ip address and port to connect to
      Address = Struct.new(:host_name, :ip_address, :port) do
        def to_s
          "#{host_name}[#{ip_address}]:#{port}"
        end
      end

      # Returns [Array<String>] ip addresses for the supplied DNS entry
      # Returns dns_name if it is already an IP Address
      def self.ip_addresses(dns_name)
        getaddrinfo(dns_name, nil, AF_INET, SOCK_STREAM).collect { |s| s[3] }
      end

      # Create socket instance from the following parameters:
      #   address [Net::TCPClient::Socket::Address]
      #     Host name, ip address and port of server to connect to
      #
      #   buffered [true|false]
      #     Allow socket to buffer data sent or received.
      #     Buffering is good for large data transfers.
      #     Buffering should not be used for RPC style applications.
      #     Default: true
      def initialize(params)
        params    = params.dup
        @address  = params.delete(:address)
        buffered  = params.delete(:buffered)
        @buffered = buffered.nil? ? true : buffered
        raise(ArgumentError, "Unknown arguments: #{params.inspect}") if params.size > 0

        raise(ArgumentError, 'Missing mandatory parameter: :address') unless @address

        super(AF_INET, SOCK_STREAM, 0)
        setsockopt(IPPROTO_TCP, TCP_NODELAY, 1) unless buffered
      end

      # Connect to server
      #
      # Raises Net::TCPClient::ConnectionTimeout when the connection timeout has been exceeded
      # Raises Net::TCPClient::ConnectionFailure
      def connect(timeout)
        socket_address = self.class.pack_sockaddr_in(address.port, address.ip_address)

        # Timeout of -1 means wait forever for a connection
        return super(socket_address) if timeout == -1

        deadline = Time.now.utc + timeout
        begin
          non_blocking(deadline) { connect_nonblock(socket_address) }
        rescue Errno::EISCONN
          # Connection was successful.
        rescue NonBlockingTimeout
          raise(Net::TCPClient::ConnectionTimeout.new("Timed out after #{timeout} seconds trying to connect to #{address}"))
        end
      end

      # Returns a response from the server
      #
      # Raises Net::TCPClient::ConnectionTimeout when the time taken to create a connection
      #        exceeds the :connect_timeout
      #        Connection is closed
      # Raises Net::TCPClient::ConnectionFailure whenever Socket raises an error such as
      #        Error::EACCESS etc, see Socket#connect for more information
      #        Connection is closed
      # Raises Net::TCPClient::ReadTimeout if the timeout has been exceeded waiting for the
      #        requested number of bytes from the server
      #        Partial data will not be returned
      #        Connection is _not_ closed and #read can be called again later
      #        to read the respnse from the connection
      #
      # Parameters
      #   length [Fixnum]
      #     The number of bytes to return
      #     #read will not return until 'length' bytes have been received from
      #     the server
      #
      #   buffer [String]
      #    Optional buffer into which to write the data that is read.
      #
      #   timeout [Float]
      #     Optional: Override the default read timeout for this read
      #     Number of seconds before raising Net::TCPClient::ReadTimeout when no data has
      #     been returned
      #     A value of -1 will wait forever for a response on the socket
      #     Default: :read_timeout supplied to #initialize
      #
      #  Note: After a Net::TCPClient::ReadTimeout #read can be called again on
      #        the same socket to read the response later.
      #        If the application no longers want the connection after a
      #        Net::TCPClient::ReadTimeout, then the #close method _must_ be called
      #        before calling _connect_ or _retry_on_connection_failure_ to create
      #        a new connection
      def read(length, buffer, timeout)
        result =
          if timeout < 0
            buffer.nil? ? super(length) : super(length, buffer)
          else
            deadline = Time.now.utc + timeout
            non_blocking(deadline) do
              buffer.nil? ? read_nonblock(length) : read_nonblock(length, buffer)
            end
          end

        # EOF before all the data was returned
        if result.nil? || (result.length < length)
          logger.warn "#read server closed the connection before #{length} bytes were returned" if respond_to?(:logger)
          raise Net::TCPClient::ConnectionFailure.new('Connection lost while reading data', address.to_s, EOFError.new('end of file reached'))
        end
        result
      rescue NonBlockingTimeout
        logger.warn "#read Timeout after #{timeout} seconds" if respond_to?(:logger)
        raise Net::TCPClient::ReadTimeout.new("Timed out after #{timeout} seconds trying to read from #{address}")
      rescue SystemCallError, IOError => exception
        logger.warn "#read Connection failure while reading data: #{exception.class}: #{exception.message}" if respond_to?(:logger)
        raise Net::TCPClient::ConnectionFailure.new("#{exception.class}: #{exception.message}", address.to_s, exception)
      end

      # Send data to the server
      #
      # Use #with_retry to add resilience to the #send method
      #
      # Raises Net::TCPClient::ConnectionFailure whenever the send fails
      #        For a description of the errors, see Socket#write
      #
      # Parameters
      #   timeout [Float]
      #     Optional: Override the default write timeout for this write
      #     Number of seconds before raising Net::TCPClient::WriteTimeout when no data has
      #     been written.
      #     A value of -1 will wait forever
      #
      #  Note: After a Net::TCPClient::ReadTimeout #read can be called again on
      #        the same socket to read the response later.
      #        If the application no longers want the connection after a
      #        Net::TCPClient::ReadTimeout, then the #close method _must_ be called
      #        before calling _connect_ or _retry_on_connection_failure_ to create
      #        a new connection
      def write(data, timeout)
        if timeout < 0
          super(data)
        else
          deadline = Time.now.utc + timeout
          non_blocking(deadline) do
            write_nonblock(data)
          end
        end
      rescue NonBlockingTimeout
        logger.warn "#write Timeout after #{timeout} seconds" if respond_to?(:logger)
        raise Net::TCPClient::WriteTimeout.new("Timed out after #{timeout} seconds trying to write to #{address}")
      rescue SystemCallError => exception
        logger.warn "#write Connection failure: #{exception.class}: #{exception.message}" if respond_to?(:logger)
        raise Net::TCPClient::ConnectionFailure.new("Send Connection failure: #{exception.class}: #{exception.message}", address.to_s, exception)
      end

      # Returns whether the connection to the server is alive
      #
      # It is useful to call this method before making a call to the server
      # that would change data on the server
      #
      # Note: This method is only useful if the server closed the connection or
      #       if a previous connection failure occurred.
      #       If the server is hard killed this will still return true until one
      #       or more writes are attempted
      #
      # Note: In testing the overhead of this call is rather low, with the ability to
      # make about 120,000 calls per second against an active connection.
      # I.e. About 8.3 micro seconds per call
      def alive?
        return false if closed?

        if IO.select([self], nil, nil, 0)
          !eof? rescue false
        else
          true
        end
      rescue IOError
        false
      end

      private

      class NonBlockingTimeout< ::SocketError
      end

      def check_time_remaining(deadline)
        time_remaining = deadline - Time.now.utc
        raise NonBlockingTimeout if time_remaining < 0
        time_remaining
      end

      def non_blocking(deadline)
        yield
      rescue IO::WaitReadable
        time_remaining = check_time_remaining(deadline)
        raise NonBlockingTimeout unless IO.select([self], nil, nil, time_remaining)
        retry
      rescue IO::WaitWritable
        time_remaining = check_time_remaining(deadline)
        raise NonBlockingTimeout unless IO.select(nil, [self], nil, time_remaining)
        retry
      end

    end
  end
end
