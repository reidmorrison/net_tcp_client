require_relative '../lib/net/tcp_client.rb'

client = Net::TCPClient.new(
server:                 'localhost:1234',
connect_retry_interval: 0.1,
connect_retry_count:    5
)

client.retry_on_connection_failure do
client.send('Update the database')
end

# Read upto 20 characters from the server
response = client.read(20)

puts "Received: #{response}"
client.close
