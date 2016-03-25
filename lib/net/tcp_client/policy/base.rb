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
            Custom.new(server_names, policy)
          else
            raise(ArgumentError, "Invalid policy: #{policy.inspect}")
          end
        end

        def initialize(server_names)
          # Collect Addresses for the supplied server_names
          @addresses = Array(server_names).collect { |name| Address.addresses_for_server_name(name) }.flatten
        end

        # Calls the block once for each server, with the addresses in order
        def each(&block)
          raise NotImplementedError
        end

      end
    end
  end
end
