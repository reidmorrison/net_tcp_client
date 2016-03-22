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
      def connect(timeout = -1)
        socket_address = self.class.pack_sockaddr_in(address.port, address.ip_address)

        # Timeout of -1 means wait forever for a connection
        if timeout == -1
          begin
            return super(socket_address)
          rescue Errno::ETIMEDOUT
            raise Net::TCPClient::ConnectionTimeout.new("Timed out trying to connect to #{address}")
          end
        end

        begin
          connect_nonblock(socket_address)
        rescue Errno::EINPROGRESS
        end
        if IO.select(nil, [self], nil, timeout)
          begin
            connect_nonblock(socket_address)
          rescue Errno::EISCONN
          end
        else
          raise Net::TCPClient::ConnectionTimeout.new("Timed out after #{timeout} seconds trying to connect to #{address}")
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
      def read(length, buffer, timeout = -1)
        result = nil
        wait_for_data(timeout)

        # Read data from socket
        begin
          result = buffer.nil? ? super(length) : super(length, buffer)

          # EOF before all the data was returned
          if result.nil? || (result.length < length)
            logger.warn "#read server closed the connection before #{length} bytes were returned" if respond_to?(:logger)
            raise Net::TCPClient::ConnectionFailure.new('Connection lost while reading data', address.to_s, EOFError.new('end of file reached'))
          end
        rescue SystemCallError, IOError => exception
          logger.warn "#read Connection failure while reading data: #{exception.class}: #{exception.message}" if respond_to?(:logger)
          raise Net::TCPClient::ConnectionFailure.new("#{exception.class}: #{exception.message}", address.to_s, exception)
        end
        result
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
      #     Default: :write_timeout supplied to #initialize
      #
      #  Note: After a Net::TCPClient::ReadTimeout #read can be called again on
      #        the same socket to read the response later.
      #        If the application no longers want the connection after a
      #        Net::TCPClient::ReadTimeout, then the #close method _must_ be called
      #        before calling _connect_ or _retry_on_connection_failure_ to create
      #        a new connection
      def write(data, timeout = -1)
        begin
          super(data)
        rescue SystemCallError => exception
          logger.warn "#write Connection failure: #{exception.class}: #{exception.message}" if respond_to?(:logger)
          raise Net::TCPClient::ConnectionFailure.new("Send Connection failure: #{exception.class}: #{exception.message}", address.to_s, exception)
        end
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

      # Return once data is ready to be ready
      # Raises Net::TCPClient::ReadTimeout if the timeout is exceeded
      def wait_for_data(timeout)
        return if timeout == -1

        ready = false
        begin
          ready = IO.select([self], nil, [self], timeout)
        rescue IOError => exception
          logger.warn "#read Connection failure while waiting for data: #{exception.class}: #{exception.message}" if respond_to?(:logger)
          raise Net::TCPClient::ConnectionFailure.new("#{exception.class}: #{exception.message}", address.to_s, exception)
        end

        unless ready
          logger.warn "#read Timeout after #{timeout} seconds" if respond_to?(:logger)
          raise Net::TCPClient::ReadTimeout.new("Timedout after #{timeout} seconds trying to read from #{address}")
        end
      end

    end
  end
end
