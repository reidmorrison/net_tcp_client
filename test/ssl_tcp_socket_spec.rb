$LOAD_PATH.unshift File.dirname(__FILE__) + '/../lib'
$LOAD_PATH.unshift File.dirname(__FILE__)

require 'test/unit'
require 'shoulda'
require 'net/tcp_client'


class TCPSSLClientTest < Test::Unit::TestCase
  context Net::TCPClient do
    setup do
      @client = Net::TCPClient.new(server: 'localhost:1234',
                                   connect_retry_interval: 0.1,
                                   connect_retry_count:    5,
                                   use_ssl:                true,
                                   expected_cert_path:     "/Users/brad/projects/powerplus/net_tcp_client/test/certificate.pem")
    end
    should 'be able to connect to an SSL server' do
      assert @client.alive?
    end
    should 'be able to write and read data from an SSL server' do
      test_string = "pew\n"
      bytes_sent = @client.write(test_string)
      assert_equal bytes_sent, test_string.length
      assert_equal @client.read(bytes_sent), test_string
    end
    should 'be able to report an invalid certificate'
  end
end
