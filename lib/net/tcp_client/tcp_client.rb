require 'forwardable'
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
    extend Forwardable

    attr_accessor :connect_timeout, :read_timeout, :write_timeout,
      :connect_retry_count, :connect_retry_interval, :retry_count,
      :policy, :close_on_error, :buffered

    def_delegators :@socket, :closed?, :eof?, :setsockopt, :alive?

    # Returns the logger being used by the TCPClient instance
    attr_reader :logger, :socket

    # Supports embedding user supplied data along with this connection
    # such as sequence number and other connection specific information
    # Not used or modified by TCPClient
    attr_accessor :user_data

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
      Net::TCPClient::ConnectionTimeout
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
    #     '192.168.1.10:80'
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
    #   :connect_timeout [Float]
    #     Time in seconds to timeout when trying to connect to the server
    #     A value of -1 will cause the connect wait time to be infinite
    #     Default: Half of the :read_timeout ( 30 seconds )
    #
    #   :read_timeout [Float]
    #     Time in seconds to timeout on read
    #     Can be overridden by supplying a timeout in the read call
    #     Default: 60
    #
    #   :write_timeout [Float]
    #     Time in seconds to timeout on write
    #     Can be overridden by supplying a timeout in the write call
    #     Default: 60
    #
    #   :logger [Logger]
    #     Optional: Set the logger to which to write log messages to
    #
    #   :log_level [Symbol]
    #     Optional: Set the logging level for the TCPClient
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
    #   :policy [Symbol|Proc]
    #     Specify the policy to use when connecting to servers.
    #       :ordered
    #         Select a server in the order supplied in the array, with the first
    #         having the highest priority. The second server will only be connected
    #         to if the first server is unreachable
    #       :random
    #         Randomly select a server from the list every time a connection
    #         is established, including during automatic connection recovery.
    #       :ping_time
    #         FUTURE - Not implemented yet - Pull request anyone?
    #         The server with the lowest ping time will be tried first
    #       Proc:
    #         When a Proc is supplied, it will be called passing in the list
    #         of servers. The Proc must return one server name
    #           Example:
    #             :policy => Proc.new do |servers|
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
      @write_timeout          = (params.delete(:write_timeout) || 60.0).to_f
      @connect_timeout        = (params.delete(:connect_timeout) || (@read_timeout/2)).to_f
      buffered                = params.delete(:buffered)
      @buffered               = buffered.nil? ? true : buffered
      @connect_retry_count    = params.delete(:connect_retry_count) || 10
      @retry_count            = params.delete(:retry_count) || 3
      @connect_retry_interval = (params.delete(:connect_retry_interval) || 0.5).to_f
      @on_connect             = params.delete(:on_connect)
      @policy                 = params.delete(:policy) || params.delete(:server_selector) || :ordered
      @close_on_error         = params.delete(:close_on_error)
      @close_on_error         = true if @close_on_error.nil?

      unless @logger = params.delete(:logger)
        if defined?(SemanticLogger::Logger)
          @logger = SemanticLogger::Logger.new(self.class, params.delete(:log_level))
        else
          # Create a nil logger
          require 'logger'
          @logger       = Logger.new($null)
          @logger.level = Logger::FATAL
        end
      end

      if server = params.delete(:server)
        @servers = [server]
      end
      if servers = params.delete(:servers)
        @servers = servers
      end
      raise(ArgumentError, 'Missing mandatory :server or :servers') unless @servers

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
      start_time = Time.now
      retries    = 0
      close

      # Number of times to try
      begin
        @socket = connect_to_server(servers, policy)
        logger.info "Connected to #{socket.address} after #{'%.1f' % (Time.now - start_time)}ms"
      rescue ::SocketError, SystemCallError => exception
        # Retry-able?
        if self.class.reconnect_on_errors.include?(exception.class) && (retries < connect_retry_count.to_i)
          retries += 1
          logger.warn "Going to retry connecting to servers. Sleeping:#{connect_retry_interval}s. Retry: #{retries}"
          sleep(connect_retry_interval)
          retry
        else
          message = "Failed to connect to any of #{servers.join(',')} after #{retries} retries"
          if defined?(SemanticLogger::Logger) && logger.is_a?(SemanticLogger::Logger)
            logger.benchmark_error(message, exception: exception, duration: (Time.now - start_time))
          else
            logger.error(" and #{'%.1f' % (Time.now - start_time)}ms. #{message}: Exception: #{exception.class}: #{exception.message}\n#{(exception.backtrace || []).join("\n")}")
          end
          raise(Net::TCPClient::ConnectionFailure.new(message, servers, exception))
        end
      end
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
    def write(data, timeout = write_timeout)
      @socket.write(data, timeout)
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
    #  Note: After a Net::TCPClient::ReadTimeout #read can be called again on
    #        the same socket to read the response later.
    #        If the application no longers want the connection after a
    #        Net::TCPClient::ReadTimeout, then the #close method _must_ be called
    #        before calling _connect_ or _retry_on_connection_failure_ to create
    #        a new connection
    def read(length, buffer = nil, timeout = read_timeout)
      @socket.read(length, buffer, timeout)
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
        raise Net::TCPClient::ConnectionFailure.new("After #{retries} retries to host '#{server}': #{exc_str}", server, exception.cause)
      end
    end

    def close
      @socket.close if @socket
      @socket = nil
      true
    end

    # Returns [Symbol|Proc]the current policy
    # [DEPRECATED]
    def server_selector
      warn '[Deprecated] Use #policy instead of #server_selector'
      policy
    end

    # Returns [Symbol|Proc]the current policy
    # [DEPRECATED]
    def server_selector=(selecter)
      warn '[Deprecated] Use #policy= instead of #server_selector='
      self.policy = selecter
    end

    # Returns [String] Name of the server connected to including the port number
    #
    # Example:
    #   localhost:2000
    #
    # [DEPRECATED]
    def server
      socket ? socket.address.to_s : nil
    end

    private

    attr_reader :servers

    # Connect to one of the servers in the list, per the current policy
    # Returns [Socket] the socket connected to or an Exception
    def connect_to_server(servers, policy)
      # Iterate over each server address until it successfully connects to a host
      last_exception = nil
      Policy::Base.factory(policy, servers).each do |address|
        begin
          return connect_to_address(address)
        rescue Net::TCPClient::ConnectionTimeout, SystemCallError => exception
          logger.warn "Unable to connect to: #{address}: #{exception.class}: #{exception.message}"
          last_exception = exception
        end
      end

      # Raise Exception once it has failed to connect to any server
      last_exception ? raise(last_exception) : raise(ArgumentError, "No servers supplied to connect to: #{servers.join(',')}")
    end

    # Connect to the server at the supplied address
    # Returns the socket connection
    def connect_to_address(address)
      socket = Net::TCPClient::Socket.new(
        address:        address,
        logger:         logger,
        close_on_error: close_on_error,
        buffered:       buffered
      )
      socket.connect(connect_timeout)

      # Invoke user supplied Block every time a new connection has been established
      @on_connect.call(self) if @on_connect
      socket
    end

  end
end
