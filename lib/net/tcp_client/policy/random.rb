module Net
  class TCPClient
    module Policy
      # Policy for connecting to servers in the order specified
      class Random < Base
        # Calls the block once for each server, with the addresses in random order
        def each(&block)
          addresses.shuffle.each {|address| block.call(address)}
        end

      end
    end
  end
end
