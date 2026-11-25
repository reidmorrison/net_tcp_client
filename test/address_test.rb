require_relative "test_helper"
require "ipaddr"

class Net::TCPClient::AddressTest < Minitest::Test
  describe Net::TCPClient::Address do
    describe ".ip_addresses" do
      it "returns the ip addresses for a known DNS" do
        ips = Net::TCPClient::Address.ip_addresses("google.com")
        assert ips.count.positive?
        ips.each do |ip|
          # Validate IP Addresses
          IPAddr.new(ip)
        end
      end

      it "returns an ip address" do
        ips = Net::TCPClient::Address.ip_addresses("127.0.0.1")
        assert_equal 1, ips.count
        assert_equal "127.0.0.1", ips.first
      end

      it "returns an IPv6 address" do
        assert_equal ["::1"], Net::TCPClient::Address.ip_addresses("::1")
      end

      it "returns the IPv4 addresses before the IPv6 addresses" do
        ips = Net::TCPClient::Address.ip_addresses("localhost")
        assert_equal "127.0.0.1", ips.first
        families = ips.map { |ip| IPAddr.new(ip).ipv4? ? :ipv4 : :ipv6 }
        assert_equal families.sort_by { |f| f == :ipv4 ? 0 : 1 }, families
      end
    end

    describe ".addresses" do
      it "returns the addresses for a known DNS, IPv4 first" do
        addresses = Net::TCPClient::Address.addresses("localhost", 80)
        refute_empty addresses, addresses.ai
        address = addresses.first
        assert_equal 80, address.port
        assert_equal "127.0.0.1", address.ip_address
        assert_equal "localhost", address.host_name
      end

      it "returns addresses for a DNS with mutiple IPs" do
        addresses = Net::TCPClient::Address.addresses("google.com", 80)
        assert addresses.count.positive?
        addresses.each do |address|
          # Validate IP Addresses
          IPAddr.new(address.ip_address)
          assert_equal 80, address.port
          assert_equal "google.com", address.host_name
        end
      end

      it "returns an ip address" do
        addresses = Net::TCPClient::Address.addresses("127.0.0.1", 80)
        assert_equal 1, addresses.count
        address = addresses.first
        assert_equal 80, address.port
        assert_equal "127.0.0.1", address.ip_address
        assert_equal "127.0.0.1", address.host_name
      end
    end

    describe ".addresses_for_server_name" do
      it "returns addresses for server name" do
        addresses = Net::TCPClient::Address.addresses_for_server_name("localhost:80")
        refute_empty addresses, addresses.ai
        address = addresses.first
        assert_equal 80, address.port
        assert_equal "127.0.0.1", address.ip_address
        assert_equal "localhost", address.host_name
      end

      it "returns an ip address" do
        addresses = Net::TCPClient::Address.addresses_for_server_name("127.0.0.1:80")
        assert_equal 1, addresses.count
        address = addresses.first
        assert_equal 80, address.port
        assert_equal "127.0.0.1", address.ip_address
        assert_equal "127.0.0.1", address.host_name
      end

      it "returns an IPv6 address in square brackets" do
        addresses = Net::TCPClient::Address.addresses_for_server_name("[::1]:80")
        assert_equal 1, addresses.count
        address = addresses.first
        assert_equal 80, address.port
        assert_equal "::1", address.ip_address
        assert_equal "::1", address.host_name
      end

      ["::1:80", "[::1]", "localhost", "localhost:", "localhost:0", "localhost:http", ":80", "[]:80"].each do |name|
        it "rejects #{name.inspect}" do
          assert_raises(ArgumentError) { Net::TCPClient::Address.addresses_for_server_name(name) }
        end
      end
    end

    describe "#family" do
      it "is AF_INET for an IPv4 address" do
        assert_equal Socket::AF_INET, Net::TCPClient::Address.new("localhost", "127.0.0.1", 80).family
      end

      it "is AF_INET6 for an IPv6 address" do
        assert_equal Socket::AF_INET6, Net::TCPClient::Address.new("localhost", "::1", 80).family
      end
    end

    describe "#sockaddr" do
      it "packs an IPv4 address" do
        address = Net::TCPClient::Address.new("localhost", "127.0.0.1", 80)
        assert_equal ["127.0.0.1", 80], Addrinfo.new(address.sockaddr).ip_unpack
      end

      it "packs an IPv6 address" do
        address = Net::TCPClient::Address.new("localhost", "::1", 80)
        assert_equal ["::1", 80], Addrinfo.new(address.sockaddr).ip_unpack
      end
    end

    describe ".new" do
      it "creates an address" do
        address = Net::TCPClient::Address.new("host_name", "ip_address", "2000")
        assert_equal "host_name", address.host_name
        assert_equal "ip_address", address.ip_address
        assert_equal 2000, address.port
      end
    end

    describe "#to_s" do
      it "returns a string of the address" do
        address = Net::TCPClient::Address.new("host_name", "ip_address", "2000")
        assert_equal "host_name[ip_address]:2000", address.to_s
      end
    end
  end
end
