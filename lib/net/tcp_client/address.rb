require "socket"
require "ipaddr"
module Net
  class TCPClient
    # Host name, ip address and port to connect to
    class Address
      attr_accessor :host_name, :ip_address, :port

      # Returns [Array<String>] the IPv4 and IPv6 addresses for the supplied DNS entry.
      # Returns dns_name if it is already an IP Address.
      #
      # IPv4 addresses are listed before IPv6 addresses, each in the order the resolver returns them,
      # so a host that has both still connects over IPv4 first, as it always has.
      def self.ip_addresses(dns_name)
        infos = Addrinfo.getaddrinfo(dns_name, nil, Socket::AF_UNSPEC, Socket::SOCK_STREAM)
        ipv4, ipv6 = infos.select { |info| info.ipv4? || info.ipv6? }.partition(&:ipv4?)
        (ipv4 + ipv6).map(&:ip_address).uniq
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
      # server_name should be either a host_name, or ip address combined with a port.
      # An IPv6 address must be enclosed in square brackets:
      #   "host_name:1234"
      #   "192.168.1.10:80"
      #   "[2001:db8::1]:80"
      def self.addresses_for_server_name(server_name)
        dns_name, port = parse_server_name(server_name)
        unless dns_name && port&.positive?
          raise(
            ArgumentError,
            "Invalid host_name: #{server_name.inspect}. " \
            "Must be formatted as 'host_name:1234', '192.168.1.10:80' or '[2001:db8::1]:80'"
          )
        end

        addresses(dns_name, port)
      end

      # Returns [String, Integer] the host name and port in the supplied server name,
      # or nil for either one it does not have.
      def self.parse_server_name(server_name)
        match = server_name.to_s.match(/\A(?:\[(?<ipv6>[^\]]+)\]|(?<host>[^:\[\]]+)):(?<port>\d+)\z/)
        return unless match

        [match[:ipv6] || match[:host], match[:port].to_i]
      end
      private_class_method :parse_server_name

      def initialize(host_name, ip_address, port)
        @host_name  = host_name
        @ip_address = ip_address
        @port       = port.to_i
      end

      # Returns [Integer] the address family of this address: Socket::AF_INET or Socket::AF_INET6
      def family
        addrinfo.afamily
      end

      # Returns [String] the packed socket address to connect to
      def sockaddr
        addrinfo.to_sockaddr
      end

      def to_s
        "#{host_name}[#{ip_address}]:#{port}"
      end

      private

      # The ip address is numeric, so this does not look up DNS.
      def addrinfo
        Addrinfo.tcp(ip_address, port)
      end
    end
  end
end
