module Net
  class TCPClient
    module Policy
      # Policy for connecting to servers in the order specified
      class Ordered < Base
        # Calls the block once for each server, with the addresses in order
        def each(&block)
          addresses.each {|address| block.call(address)}
        end

      end
    end
  end
end
