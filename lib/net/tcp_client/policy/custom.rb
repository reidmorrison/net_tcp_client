module Net
  class TCPClient
    module Policy
      # Policy for connecting to servers in the order specified
      class Custom < Base
        def initialize(server_names, block)
          super(server_names)
          @block = block
        end

        # Calls the block once for each server, with the addresses in the order returned
        # by the supplied block.
        # The block must return a Net::TCPClient::Address instance,
        # or nil to stop trying to connect to servers
        #
        # Note:
        #   If every address fails the block will be called constantly until it returns nil.
        #
        # Example:
        #   # Returns addresses in random order but without checking if a host name has been used before
        #   policy.each do |addresses, count|
        #     # Return nil after the last address has been tried so that retry logic can take over
        #     if count <= address.size
        #       addresses.sample
        #     end
        #   end
        def each(&block)
          count = 1
          while address = @block.call(addresses, count)
            raise(ArgumentError, 'Proc must return Net::TCPClient::Address, or nil') unless address.is_a?(Net::TCPClient::Address) || address.nil?
            block.call(address)
            count += 1
          end
        end

      end
    end
  end
end
