require_relative '../test_helper'
class Net::TCPClient::Policy::NearestTest < Minitest::Test
  describe Net::TCPClient::Policy::Nearest do
    describe '#each' do
      it 'must return one server, once' do
        servers   = ['localhost:80']
        policy    = Net::TCPClient::Policy::Nearest.new(servers)
        collected = []
        policy.each { |address| collected << address }
        assert_equal 1, collected.size
        address = collected.first
        assert_equal 80, address.port
        assert_equal 'localhost', address.host_name
        assert_equal '127.0.0.1', address.ip_address
      end

      it 'must return the servers in supplied order when they are the same distance' do
        servers = %w(10.10.10.10:80 10.10.10.10:81 10.10.10.10:82)
        # x.stub(:my_ip_address, '10.10.10.10:80'
        policy  = Net::TCPClient::Policy::Nearest.new(servers)
        names   = []
        policy.each { |address| names << address.host_name }
        assert_equal %w(10.10.10.10 10.10.10.10 10.10.10.10), names
      end

      it 'must handle an empty list of servers' do
        servers = []
        policy  = Net::TCPClient::Policy::Nearest.new(servers)
        names   = []
        policy.each { |address| names << address.host_name }
        assert_equal [], names
      end
    end

  end
end
