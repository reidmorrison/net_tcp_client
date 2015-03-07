require_relative '../lib/net/tcp_client.rb'
require 'openssl'

def calc_vli(message)
    length = message.size
    if length > 65535
      raise ArgumentError, "Message too big"
    end
    vli = [length].pack("n")
    return vli
end

p '**connecting...'
# client = Net::TCPClient.new(
#   server:                 '41.204.194.188:8955',
#   connect_retry_interval: 0.1,
#   connect_retry_count:    5,
#   read_timeout:           10,
#   use_ssl:                true,
#   expected_cert_path:     "/Users/brad/projects/powerplus/net_tcp_client/test/bizswitch.pem"
# )
# p 'connected!'
rand_id = rand(999999999999).to_s.center(10, rand(9).to_s).to_i
string = "<ipayMsg client='StonehouseSA' term='00001' seqNum='1' time='2015-03-05 22:59:56 +0200'>  <elecMsg ver='2.37'>    <vendReq>      <ref>#{rand_id}</ref>      <amt cur='ZAR'>1337</amt>      <numTokens>1</numTokens>      <meter>A12C3456789</meter>      <payType>creditCard</payType>    </vendReq></elecMsg></ipayMsg>"

vli = calc_vli(string)
# client.retry_on_connection_failure do
#   client.write("#{vli}#{string}")
# end

# response_length = client.read(2)
# p "response_length = #{response_length}"
# len = response_length.unpack("n")
# p "len = #{len}"
# bytes_to_read = len[0]
# p "bytes_to_read = #{bytes_to_read}"
# p "bytes_to_read = #{bytes_to_read-2}"
# response = client.read()

# puts "Received: #{response}"
# client.close

@host = "41.204.194.188"
@port = 8955
@use_ssl = true
@expected_cert_path = "/Users/brad/projects/powerplus/net_tcp_client/test/bizswitch.pem"
@timeout = 100

def socket_send(vli, message)
    Net::TCPClient.connect(
      server:                 "#{@host}:#{@port}",
      connect_retry_interval: 0.5,
      connect_retry_count:    3,
      read_timeout:           @timeout,
      use_ssl:                @use_ssl,
      check_length: 		  true,
      expected_cert_path:     @expected_cert_path
    ) do |client|
      # If the connection is lost, create a new one and retry the send
      client.retry_on_connection_failure do
        puts "sending: #{vli}#{message}"
        client.write("#{vli}#{message}")
      end
      # response_length = client.read(2)
      # len = response_length.unpack("n")
      # bytes_to_read = len[0]
      response = client.read()
      puts "ipay response = #{response}"
    end
  end

  socket_send(vli, string)