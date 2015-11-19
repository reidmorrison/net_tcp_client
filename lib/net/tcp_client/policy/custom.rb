module Net
  class TCPClient
    module Policy
      # Policy for connecting to servers in the order specified
      class Custom < Base
        # Calls the block once for each server, with the addresses in the order returned
        # by the supplied proc.
        # The block must return a Net::TCPClient::Socket::Address instance,
        # or nil to stop trying to connect to servers
        #
        # Note:
        #   The block will be called constantly until nil is returned by the proc
        #
        # TODO: Support Fibers
        #
        # Example:
        #   # Returns addresses in random order but without checking if a host name has been used before
        #   policy.each_proc do |addresses, count|
        #     count == addresses.size ? nil : addresses.sample
        #   end
        def each_proc(proc, &block)
          count = 1
          while address = proc.call(addresses, count)
            raise(ArgumentError, 'Proc must return Net::TCPClient::Socket::Address, or nil') unless address.is_a?(Net::TCPClient::Socket::Address) || address.nil?
            addresses.shuffle.each {|address| block.call}
          end
        end

      end
    end
  end
end
