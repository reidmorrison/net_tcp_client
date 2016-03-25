require 'socket'
require 'ipaddr'
module Net
  class TCPClient
    # Host name, ip address and port to connect to
    class Address
      attr_accessor :host_name, :ip_address, :port

      # Returns [Array<String>] ip addresses for the supplied DNS entry
      # Returns dns_name if it is already an IP Address
      def self.ip_addresses(dns_name)
        ips = []
        Socket.getaddrinfo(dns_name, nil, Socket::AF_INET, Socket::SOCK_STREAM).each do |s|
          ips << s[3] if s[0] == 'AF_INET'
        end
        ips.uniq
      end

      # Returns [Array<Net::TCPClient::Address>] addresses for a given DNS / host name.
      # The Addresses will contain the resolved ip address, host name, and port number.
      #
      # Note:
      #   Multiple ip addresses will be returned when a DNS entry has multiple ip addresses associated with it.
      def self.addresses(dns_name, port)
        ip_addresses(dns_name).collect { |ip| new(dns_name, ip, port) }
      end

      # Returns [Array<Net::TCPClient::Address>] addresses for a list of DNS / host name's
      # that are paired with their numbers
      #
      # server_name should be either a host_name, or ip address combined with a port:
      #   "host_name:1234"
      #   "192.168.1.10:80"
      def self.addresses_for_server_name(server_name)
        dns_name, port = server_name.split(':')
        port           = port.to_i
        raise(ArgumentError, "Invalid host_name: #{server_name.inspect}. Must be formatted as 'host_name:1234' or '192.168.1.10:80'") unless dns_name && (port > 0)
        addresses(dns_name, port)
      end

      def initialize(host_name, ip_address, port)
        @host_name  = host_name
        @ip_address = ip_address
        @port       = port.to_i
      end

      def to_s
        "#{host_name}[#{ip_address}]:#{port}"
      end
    end

  end
end
