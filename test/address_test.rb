require_relative 'test_helper'
require 'ipaddr'

class Net::TCPClient::AddressTest < Minitest::Test
  describe Net::TCPClient::Address do
    describe '.ip_addresses' do
      it 'returns the ip addresses for a known DNS' do
        ips = Net::TCPClient::Address.ip_addresses('google.com')
        assert ips.count > 0
        ips.each do |ip|
          # Validate IP Addresses
          IPAddr.new(ip)
        end
      end

      it 'returns an ip address' do
        ips = Net::TCPClient::Address.ip_addresses('127.0.0.1')
        assert_equal 1, ips.count
        assert_equal '127.0.0.1', ips.first
      end
    end

    describe '.addresses' do
      it 'returns one address for a known DNS' do
        addresses = Net::TCPClient::Address.addresses('localhost', 80)
        assert_equal 1, addresses.count, addresses.ai
        address = addresses.first
        assert_equal 80, address.port
        assert_equal '127.0.0.1', address.ip_address
        assert_equal 'localhost', address.host_name
      end

      it 'returns addresses for a DNS with mutiple IPs' do
        addresses = Net::TCPClient::Address.addresses('google.com', 80)
        assert addresses.count > 0
        addresses.each do |address|
          # Validate IP Addresses
          IPAddr.new(address.ip_address)
          assert_equal 80, address.port
          assert_equal 'google.com', address.host_name
        end
      end

      it 'returns an ip address' do
        addresses = Net::TCPClient::Address.addresses('127.0.0.1', 80)
        assert_equal 1, addresses.count
        address = addresses.first
        assert_equal 80, address.port
        assert_equal '127.0.0.1', address.ip_address
        assert_equal '127.0.0.1', address.host_name
      end
    end

    describe '.addresses_for_server_name' do
      it 'returns addresses for server name' do
        addresses = Net::TCPClient::Address.addresses_for_server_name('localhost:80')
        assert_equal 1, addresses.count, addresses.ai
        address = addresses.first
        assert_equal 80, address.port
        assert_equal '127.0.0.1', address.ip_address
        assert_equal 'localhost', address.host_name
      end

      it 'returns an ip address' do
        addresses = Net::TCPClient::Address.addresses_for_server_name('127.0.0.1:80')
        assert_equal 1, addresses.count
        address = addresses.first
        assert_equal 80, address.port
        assert_equal '127.0.0.1', address.ip_address
        assert_equal '127.0.0.1', address.host_name
      end
    end

    describe '.new' do
      it 'creates an address' do
        address = Net::TCPClient::Address.new('host_name', 'ip_address', '2000')
        assert_equal 'host_name', address.host_name
        assert_equal 'ip_address', address.ip_address
        assert_equal 2000, address.port
      end
    end

    describe '#to_s' do
      it 'returns a string of the address' do
        address = Net::TCPClient::Address.new('host_name', 'ip_address', '2000')
        assert_equal 'host_name[ip_address]:2000', address.to_s
      end
    end

  end
end
