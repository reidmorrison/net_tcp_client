module Net
  # Make Socket calls resilient by adding timeouts, retries and specific
  # exception categories
  #
  # TCP Client with:
  # * Connection Timeouts
  #   Ability to timeout if a connect does not complete within a reasonable time
  #   For example, this can occur when the server is turned off without shutting down
  #   causing clients to hang creating new connections
  #
  # * Automatic retries on startup connection failure
  #   For example, the server is being restarted while the client is starting
  #   Gives the server a few seconds to restart to
  #
  # * Automatic retries on active connection failures
  #   If the server is restarted during
  #
  # Connection and Read Timeouts are fully configurable
  #
  # Raises Net::TCPClient::ConnectionTimeout when the connection timeout is exceeded
  # Raises Net::TCPClient::ReadTimeout when the read timeout is exceeded
  # Raises Net::TCPClient::ConnectionFailure when a network error occurs whilst reading or writing
  #
  # Note: Only the following methods currently have auto-reconnect enabled:
  #  * read
  #  * write
  #
  # Future:
  # * Add auto-reconnect feature to sysread, syswrite, etc...
  # * To be a drop-in replacement to TCPSocket should also need to implement the
  #   following TCPSocket instance methods:  :addr, :peeraddr
  #
  # Design Notes:
  # * Does not inherit from Socket or TCP Socket because the socket instance
  #   has to be completely destroyed and recreated after a connection failure
  #
  class TCPClient
    # Supports embedding user supplied data along with this connection
    # such as sequence number and other connection specific information
    attr_accessor :user_data

    # Returns [String] Name of the server connected to including the port number
    #
    # Example:
    #   localhost:2000
    attr_reader :server

    attr_accessor :read_timeout, :connect_timeout, :connect_retry_count,
      :retry_count, :connect_retry_interval, :server_selector, :close_on_error

    # Returns [true|false] Whether send buffering is enabled for this connection
    attr_reader :buffered

    # Returns the logger being used by the TCPClient instance
    attr_reader :logger

    @@reconnect_on_errors = [
      Errno::ECONNABORTED,
      Errno::ECONNREFUSED,
      Errno::ECONNRESET,
      Errno::EHOSTUNREACH,
      Errno::EIO,
      Errno::ENETDOWN,
      Errno::ENETRESET,
      Errno::EPIPE,
      Errno::ETIMEDOUT,
      EOFError,
    ]

    # Return the array of errors that will result in an automatic connection retry
    #  To add any additional errors to the standard list:
    #    Net::TCPClient.reconnect_on_errors << Errno::EPROTO
    def self.reconnect_on_errors
      @@reconnect_on_errors
    end

    # Create a connection, call the supplied block and close the connection on
    # completion of the block
    #
    # See #initialize for the list of parameters
    #
    # Example
    #   Net::TCPClient.connect(
    #     server:                 'server:3300',
    #     connect_retry_interval: 0.1,
    #     connect_retry_count:    5
    #   ) do |client|
    #     client.retry_on_connection_failure do
    #       client.send('Update the database')
    #     end
    #     response = client.read(20)
    #     puts "Received: #{response}"
    #   end
    #
    def self.connect(params={})
      begin
        connection = self.new(params)
        yield(connection)
      ensure
        connection.close if connection
      end
    end

    # Create a new TCP Client connection
    #
    # Parameters:
    #   :server [String]
    #     URL of the server to connect to with port number
    #     'localhost:2000'
    #
    #   :servers [Array of String]
    #     Array of URL's of servers to connect to with port numbers
    #     ['server1:2000', 'server2:2000']
    #
    #     The second server will only be attempted once the first server
    #     cannot be connected to or has timed out on connect
    #     A read failure or timeout will not result in switching to the second
    #     server, only a connection failure or during an automatic reconnect
    #
    #   :read_timeout [Float]
    #     Time in seconds to timeout on read
    #     Can be overridden by supplying a timeout in the read call
    #     Default: 60
    #
    #   :connect_timeout [Float]
    #     Time in seconds to timeout when trying to connect to the server
    #     A value of -1 will cause the connect wait time to be infinite
    #     Default: Half of the :read_timeout ( 30 seconds )
    #
    #   :logger [Logger]
    #     Set the logger to which to write log messages to
    #     Note: Additional methods will be mixed into this logger to make it
    #           compatible with the SematicLogger extensions if it is not already
    #           a SemanticLogger logger instance
    #
    #   :log_level [Symbol]
    #     Set the logging level for the TCPClient
    #     Any valid SemanticLogger log level:
    #       :trace, :debug, :info, :warn, :error, :fatal
    #     Default: SemanticLogger.default_level
    #
    #   :buffered [Boolean]
    #     Whether to use Nagle's Buffering algorithm (http://en.wikipedia.org/wiki/Nagle's_algorithm)
    #     Recommend disabling for RPC style invocations where we don't want to wait for an
    #     ACK from the server before sending the last partial segment
    #     Buffering is recommended in a browser or file transfer style environment
    #     where multiple sends are expected during a single response
    #     Default: true
    #
    #   :connect_retry_count [Fixnum]
    #     Number of times to retry connecting when a connection fails
    #     Default: 10
    #
    #   :connect_retry_interval [Float]
    #     Number of seconds between connection retry attempts after the first failed attempt
    #     Default: 0.5
    #
    #   :retry_count [Fixnum]
    #     Number of times to retry when calling #retry_on_connection_failure
    #     This is independent of :connect_retry_count which still applies with
    #     connection failures. This retry controls upto how many times to retry the
    #     supplied block should a connection failure occurr during the block
    #     Default: 3
    #
    #   :on_connect [Proc]
    #     Directly after a connection is established and before it is made available
    #     for use this Block is invoked.
    #     Typical Use Cases:
    #     - Initialize per connection session sequence numbers
    #     - Pass any authentication information to the server
    #     - Perform a handshake with the server
    #
    #   :server_selector [Symbol|Proc]
    #     When multiple servers are supplied using :servers, this option will
    #     determine which server is selected from the list
    #       :ordered
    #         Select a server in the order supplied in the array, with the first
    #         having the highest priority. The second server will only be connected
    #         to if the first server is unreachable
    #       :random
    #         Randomly select a server from the list every time a connection
    #         is established, including during automatic connection recovery.
    #       :nearest
    #         FUTURE - Not implemented yet
    #         The server with an IP address that most closely matches the
    #         local ip address will be attempted first
    #         This will result in connections to servers on the localhost
    #         first prior to looking at remote servers
    #       :ping_time
    #         FUTURE - Not implemented yet
    #         The server with the lowest ping time will be selected first
    #       Proc:
    #         When a Proc is supplied, it will be called passing in the list
    #         of servers. The Proc must return one server name
    #           Example:
    #             :server_selector => Proc.new do |servers|
    #               servers.last
    #             end
    #       Default: :ordered
    #
    #   :close_on_error [True|False]
    #     To prevent the connection from going into an inconsistent state
    #     automatically close the connection if an error occurs
    #     This includes a Read Timeout
    #     Default: true
    #
    # Example
    #   client = Net::TCPClient.new(
    #     server:                 'server:3300',
    #     connect_retry_interval: 0.1,
    #     connect_retry_count:    5
    #   )
    #
    #   client.retry_on_connection_failure do
    #     client.send('Update the database')
    #   end
    #
    #   # Read upto 20 characters from the server
    #   response = client.read(20)
    #
    #   puts "Received: #{response}"
    #   client.close
    def initialize(parameters={})
      params                  = parameters.dup
      @read_timeout           = (params.delete(:read_timeout) || 60.0).to_f
      @connect_timeout        = (params.delete(:connect_timeout) || (@read_timeout/2)).to_f
      buffered                = params.delete(:buffered)
      @buffered               = buffered.nil? ? true : buffered
      @connect_retry_count    = params.delete(:connect_retry_count) || 10
      @retry_count            = params.delete(:retry_count) || 3
      @connect_retry_interval = (params.delete(:connect_retry_interval) || 0.5).to_f
      @on_connect             = params.delete(:on_connect)
      @server_selector        = params.delete(:server_selector) || :ordered
      @close_on_error         = params.delete(:close_on_error)
      @close_on_error         = true if @close_on_error.nil?
      @logger                 = params.delete(:logger)

      if server = params.delete(:server)
        @servers = [server]
      end
      if servers = params.delete(:servers)
        @servers = servers
      end
      raise(ArgumentError, 'Missing mandatory :server or :servers') unless @servers

      # If a logger is supplied then extend it with the SemanticLogger API
      @logger = Logging.new_logger(logger, "#{self.class.name} #{@servers.inspect}", params.delete(:log_level))

      raise(ArgumentError, "Invalid options: #{params.inspect}") if params.size > 0

      # Connect to the Server
      connect
    end

    # Connect to the TCP server
    #
    # Raises Net::TCPClient::ConnectionTimeout when the time taken to create a connection
    #        exceeds the :connect_timeout
    # Raises Net::TCPClient::ConnectionFailure whenever Socket raises an error such as Error::EACCESS etc, see Socket#connect for more information
    #
    # Error handling is implemented as follows:
    # 1. TCP Socket Connect failure:
    #    Cannot reach server
    #    Server is being restarted, or is not running
    #    Retry 50 times every 100ms before raising a Net::TCPClient::ConnectionFailure
    #    - Means all calls to #connect will take at least 5 seconds before failing if the server is not running
    #    - Allows hot restart of server process if it restarts within 5 seconds
    #
    # 2. TCP Socket Connect timeout:
    #    Timed out after 5 seconds trying to connect to the server
    #    Usually means server is busy or the remote server disappeared off the network recently
    #    No retry, just raise a Net::TCPClient::ConnectionTimeout
    #
    # Note: When multiple servers are supplied it will only try to connect to
    #       the subsequent servers once the retry count has been exceeded
    #
    # Note: Calling #connect on an open connection will close the current connection
    #       and create a new connection
    def connect
      @socket.close if @socket && !@socket.closed?
      case
      when @servers.size == 1
        connect_to_server(@servers.first)
      when @server_selector.is_a?(Proc)
        connect_to_server(@server_selector.call(@servers))
      when @server_selector == :ordered
        connect_to_servers_in_order(@servers)
      when @server_selector == :random
        connect_to_servers_in_order(@servers.sample(@servers.size))
      else
        raise ArgumentError.new("Invalid or unknown value for parameter :server_selector => #{@server_selector}")
      end

      # Invoke user supplied Block every time a new connection has been established
      @on_connect.call(self) if @on_connect
      true
    end

    # Send data to the server
    #
    # Use #with_retry to add resilience to the #send method
    #
    # Raises Net::TCPClient::ConnectionFailure whenever the send fails
    #        For a description of the errors, see Socket#write
    #
    def write(data)
      data = data.to_s
      logger.trace('#write ==> sending', data)
      stats = {}
      logger.benchmark_debug('#write ==> complete', stats) do
        begin
          stats[:bytes_sent] = @socket.write(data)
        rescue SystemCallError => exception
          logger.warn "#write Connection failure: #{exception.class}: #{exception.message}"
          close if close_on_error
          raise Net::TCPClient::ConnectionFailure.new("Send Connection failure: #{exception.class}: #{exception.message}", @server, exception)
        rescue Exception
          # Close the connection on any other exception since the connection
          # will now be in an inconsistent state
          close if close_on_error
          raise
        end
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
    #     #read will not return unitl 'length' bytes have been received from
    #     the server
    #
    #   timeout [Float]
    #     Optional: Override the default read timeout for this read
    #     Number of seconds before raising Net::TCPClient::ReadTimeout when no data has
    #     been returned
    #     A value of -1 will wait forever for a response on the socket
    #     Default: :read_timeout supplied to #initialize
    #
    #  Note: After a ResilientSocket::Net::TCPClient::ReadTimeout #read can be called again on
    #        the same socket to read the response later.
    #        If the application no longers want the connection after a
    #        Net::TCPClient::ReadTimeout, then the #close method _must_ be called
    #        before calling _connect_ or _retry_on_connection_failure_ to create
    #        a new connection
    #
    def read(length, buffer = nil, timeout = read_timeout)
      result = nil
      logger.benchmark_debug("#read <== read #{length} bytes") do
        wait_for_data(timeout)

        # Read data from socket
        begin
          result = buffer.nil? ? @socket.read(length) : @socket.read(length, buffer)
          logger.trace('#read <== received', result)

          # EOF before all the data was returned
          if result.nil? || (result.length < length)
            close if close_on_error
            logger.warn "#read server closed the connection before #{length} bytes were returned"
            raise Net::TCPClient::ConnectionFailure.new('Connection lost while reading data', @server, EOFError.new('end of file reached'))
          end
        rescue SystemCallError, IOError => exception
          close if close_on_error
          logger.warn "#read Connection failure while reading data: #{exception.class}: #{exception.message}"
          raise Net::TCPClient::ConnectionFailure.new("#{exception.class}: #{exception.message}", @server, exception)
        rescue Exception
          # Close the connection on any other exception since the connection
          # will now be in an inconsistent state
          close if close_on_error
          raise
        end
      end
      result
    end

    # Send and/or receive data with automatic retry on connection failure
    #
    # On a connection failure, it will create a new connection and retry the block.
    # Returns immediately on exception Net::TCPClient::ReadTimeout
    # The connection is always closed on Net::TCPClient::ConnectionFailure regardless of close_on_error
    #
    # 1. Example of a resilient _readonly_ request:
    #
    #    When reading data from a server that does not change state on the server
    #    Wrap both the send and the read with #retry_on_connection_failure
    #    since it is safe to send the same data twice to the server
    #
    #    # Since the send can be sent many times it is safe to also put the receive
    #    # inside the retry block
    #    value = client.retry_on_connection_failure do
    #      client.send("GETVALUE:count\n")
    #      client.read(20).strip.to_i
    #    end
    #
    # 2. Example of a resilient request that _modifies_ data on the server:
    #
    #    When changing state on the server, for example when updating a value
    #    Wrap _only_ the send with #retry_on_connection_failure
    #    The read must be outside the #retry_on_connection_failure since we must
    #    not retry the send if the connection fails during the #read
    #
    #    value = 45
    #    # Only the send is within the retry block since we cannot re-send once
    #    # the send was successful since the server may have made the change
    #    client.retry_on_connection_failure do
    #      client.send("SETVALUE:#{count}\n")
    #    end
    #    # Server returns "SAVED" if the call was successfull
    #    result = client.read(20).strip
    #
    # Error handling is implemented as follows:
    #    If a network failure occurrs during the block invocation the block
    #    will be called again with a new connection to the server.
    #    It will only be retried up to 3 times
    #    The re-connect will independently retry and timeout using all the
    #    rules of #connect
    def retry_on_connection_failure
      retries = 0
      begin
        connect if closed?
        yield(self)
      rescue Net::TCPClient::ConnectionFailure => exception
        exc_str = exception.cause ? "#{exception.cause.class}: #{exception.cause.message}" : exception.message
        # Re-raise exceptions that should not be retried
        if !self.class.reconnect_on_errors.include?(exception.cause.class)
          logger.warn "#retry_on_connection_failure not configured to retry: #{exc_str}"
          raise exception
        elsif retries < @retry_count
          retries += 1
          logger.warn "#retry_on_connection_failure retry #{retries} due to #{exception.class}: #{exception.message}"
          connect
          retry
        end
        logger.error "#retry_on_connection_failure Connection failure: #{exception.class}: #{exception.message}. Giving up after #{retries} retries"
        raise Net::TCPClient::ConnectionFailure.new("After #{retries} retries to host '#{server}': #{exc_str}", @server, exception.cause)
      end
    end

    # Close the socket only if it is not already closed
    #
    # Logs a warning if an error occurs trying to close the socket
    def close
      @socket.close unless @socket.closed?
    rescue IOError => exception
      logger.warn "IOError when attempting to close socket: #{exception.class}: #{exception.message}"
    end

    # Returns whether the socket is closed
    def closed?
      @socket.closed?
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
      return false if @socket.closed?

      if IO.select([@socket], nil, nil, 0)
        !@socket.eof? rescue false
      else
        true
      end
    rescue IOError
      false
    end

    # See: Socket#setsockopt
    def setsockopt(level, optname, optval)
      @socket.setsockopt(level, optname, optval)
    end

    #############################################
    protected

    # Try connecting to a single server
    # Returns the connected socket
    #
    # Raises Net::TCPClient::ConnectionTimeout when the connection timeout has been exceeded
    # Raises Net::TCPClient::ConnectionFailure
    def connect_to_server(server)
      # Have to use Socket internally instead of TCPSocket since TCPSocket
      # does not offer async connect API amongst others:
      # :accept, :accept_nonblock, :bind, :connect, :connect_nonblock, :getpeereid,
      # :ipv6only!, :listen, :recvfrom_nonblock, :sysaccept
      retries = 0
      logger.benchmark_info "Connected to #{server}" do
        host_name, port = server.split(":")
        port            = port.to_i

        address        = Socket.getaddrinfo(host_name, nil, Socket::AF_INET).sample
        socket_address = Socket.pack_sockaddr_in(port, address[3])

        begin
          @socket = Socket.new(Socket.const_get(address[0]), Socket::SOCK_STREAM, 0)
          @socket.setsockopt(Socket::IPPROTO_TCP, Socket::TCP_NODELAY, 1) unless buffered
          if @connect_timeout == -1
            # Timeout of -1 means wait forever for a connection
            @socket.connect(socket_address)
          else
            begin
              @socket.connect_nonblock(socket_address)
            rescue Errno::EINPROGRESS
            end
            if IO.select(nil, [@socket], nil, @connect_timeout)
              begin
                @socket.connect_nonblock(socket_address)
              rescue Errno::EISCONN
              end
            else
              raise(Net::TCPClient::ConnectionTimeout.new("Timedout after #{@connect_timeout} seconds trying to connect to #{server}"))
            end
          end
          break
        rescue SystemCallError => exception
          if retries < @connect_retry_count && self.class.reconnect_on_errors.include?(exception.class)
            retries += 1
            logger.warn "Connection failure: #{exception.class}: #{exception.message}. Retry: #{retries}"
            sleep @connect_retry_interval
            retry
          end
          logger.error "Connection failure: #{exception.class}: #{exception.message}. Giving up after #{retries} retries"
          raise Net::TCPClient::ConnectionFailure.new("After #{retries} connection attempts to host '#{server}': #{exception.class}: #{exception.message}", @server, exception)
        end
      end
      @server = server
    end

    # Try connecting to each server in the order supplied
    # The next server is tried if it cannot connect to the current one
    # After the last server a ConnectionFailure will be raised
    def connect_to_servers_in_order(servers)
      exception = nil
      servers.find do |server|
        begin
          connect_to_server(server)
          exception = nil
          true
        rescue Net::TCPClient::ConnectionFailure => exc
          exception = exc
          false
        end
      end
      # Raise Exception once it has also failed to connect to all servers
      raise(exception) if exception
    end

    # Return once data is ready to be ready
    # Raises Net::TCPClient::ReadTimeout if the timeout is exceeded
    def wait_for_data(timeout)
      return if timeout == -1

      ready = false
      begin
        ready = IO.select([@socket], nil, [@socket], timeout)
      rescue IOError => exception
        logger.warn "#read Connection failure while waiting for data: #{exception.class}: #{exception.message}"
        close if close_on_error
        raise Net::TCPClient::ConnectionFailure.new("#{exception.class}: #{exception.message}", @server, exception)
      rescue Exception
        # Close the connection on any other exception since the connection
        # will now be in an inconsistent state
        close if close_on_error
        raise
      end

      unless ready
        close if close_on_error
        logger.warn "#read Timeout after #{timeout} seconds"
        raise Net::TCPClient::ReadTimeout.new("Timedout after #{timeout} seconds trying to read from #{@server}")
      end
    end

  end
end
