require_relative "../test_helper"
class Net::TCPClient::Policy::RandomTest < Minitest::Test
  describe Net::TCPClient::Policy::Random do
    describe "#each" do
      it "must return one server, once" do
        servers   = ["127.0.0.1:80"]
        policy    = Net::TCPClient::Policy::Random.new(servers)
        collected = []
        policy.each { |address| collected << address }
        assert_equal 1, collected.size
        address = collected.first
        assert_equal 80, address.port
        assert_equal "127.0.0.1", address.host_name
        assert_equal "127.0.0.1", address.ip_address
      end

      it "must return the servers in random order" do
        servers = %w[127.0.0.1:80 [::1]:2000 127.0.0.2:2100]
        policy  = Net::TCPClient::Policy::Random.new(servers)

        names = []
        # It is possible the random order is the supplied order.
        # Keep retrying until the order is different.
        3.times do
          policy.each { |address| names << address.host_name }
          break if names != %w[127.0.0.1 ::1 127.0.0.2]

          names = []
        end

        refute_equal %w[127.0.0.1 ::1 127.0.0.2], names
        assert_equal %w[127.0.0.1 ::1 127.0.0.2].sort, names.sort
      end

      it "must handle an empty list of servers" do
        servers = []
        policy  = Net::TCPClient::Policy::Random.new(servers)
        names   = []
        policy.each { |address| names << address.host_name }
        assert_equal [], names
      end
    end
  end
end
