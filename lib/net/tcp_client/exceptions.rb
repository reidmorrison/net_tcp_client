module Net
  class TCPClient

    class ConnectionTimeout < ::SocketError
    end
    class ReadTimeout < ::SocketError
    end
    class WriteTimeout < ::SocketError
    end

    # Raised by ResilientSocket whenever a Socket connection failure has occurred
    class ConnectionFailure < ::SocketError
      # Returns the host name and port against which the connection failure occurred
      attr_reader :server

      # Returns the original exception that caused the connection failure
      # For example instances of Errno::ECONNRESET
      attr_reader :cause

      # Parameters
      #   message [String]
      #     Text message of the reason for the failure and/or where it occurred
      #
      #   server [String]
      #     Hostname and port
      #     For example: "localhost:2000"
      #
      #   cause [Exception]
      #     Original Exception if any, otherwise nil
      def initialize(message, server, cause=nil)
        @server = server
        @cause  = cause
        super(message)
      end
    end

  end
end
