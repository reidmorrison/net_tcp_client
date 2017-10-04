module Net
  class TCPClient
    module Policy
      # Connect to the server with the nearest IP Address
      # Note: Currently only supports ipv4
      class Nearest < Ordered
        def initialize(server_names)
          addresses  = Array(server_names).collect { |name| Address.addresses_for_server_name(name) }.flatten
          @addresses = addresses.sort_by { |address| calculate_score(address.ip_address) }
        end

        private

        IPV4_REG_EXP = /^(\d{1,3})\.(\d{1,3})\.(\d{1,3})\.(\d{1,3})$/

        # Returns [Integer] the score for the supplied ip_address
        # Score currently ranges from 0 to 4 with 4 being the best score
        # If the IP address does not match an IP v4 address a DNS lookup will
        # be performed
        def self.calculate_score(ip_address, local_ip_address)
          ip_address   = '127.0.0.1' if ip_address == 'localhost'
          score        = 0
          # Each matching element adds 1 to the score
          # 192.168.  0.  0
          #               1
          #           1
          #       1
          #   1
          server_match = IPV4_REG_EXP.match(ip_address) || IPV4_REG_EXP.match(Resolv::DNS.new.getaddress(ip_address).to_s)
          if server_match
            local_match = IPV4_REG_EXP.match(local_ip_address)
            score       = 0
            (1..4).each do |i|
              break if local_match[i].to_i != server_match[i].to_i
              score += 1
            end
          end
          score
        end

      end
    end
  end
end
