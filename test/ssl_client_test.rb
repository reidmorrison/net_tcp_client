require_relative '../lib/net/tcp_client.rb'
require 'openssl'

p '**connecting...'
client = Net::TCPClient.new(
  server:                 'localhost:1234',
  connect_retry_interval: 0.1,
  connect_retry_count:    5,
  use_ssl:                true
)
p 'connected!'
client.retry_on_connection_failure do
  client.write(('pew' * 20) + "\n")
end

# Read upto 20 characters from the server
response = client.read(20)

puts "Received: #{response}"
client.close
