module Net
  class TCPClient
    module Policy
      # Policy for connecting to servers in the order specified
      class Base
        attr_reader :addresses

        # Returns a policy instance for the supplied policy type
        def self.factory(policy, server_names)
          case policy
          when :ordered
            # Policy for connecting to servers in the order specified
            Ordered.new(server_names)
          when :random
            Random.new(server_names)
          when Proc
            Custom.new(server_names)
          else
            raise(ArgumentError, "Invalid policy: #{policy.inspect}")
          end
        end

        # Collect all host_name, ip address, and port address combinations
        # Each DNS entry in turn may have multiple ip addresses
        # server_name should be either a host_name, or ip address combined with a port:
        #   "host_name:1234"
        #   "192.168.1.10:80"
        def self.resolve_addresses(server_names)
          addresses = []
          Array(server_names).each do |host_name|
            # TODO: Support IPv6
            dns_name, port = host_name.split(':')
            port           = port.to_i
            raise(ArgumentError, "Invalid host_name: #{host_name.inspect}. Must be formatted as 'host_name:1234' or '192.168.1.10:80'") unless dns_name && (port > 0)
            if ip_addresses = Net::TCPClient::Socket.ip_addresses(dns_name)
              ip_addresses.each { |ip| addresses << Net::TCPClient::Socket::Address.new(dns_name, ip, port) }
            end
          end
          addresses
        end

        # Resolve the ip addresses for the supplied DNS or ip names
        def initialize(server_names)
          @addresses = self.class.resolve_addresses(server_names)
        end

        # Calls the block once for each server, with the addresses in order
        def each(&block)
          raise NotImplementedError
        end

      end
    end
  end
end
