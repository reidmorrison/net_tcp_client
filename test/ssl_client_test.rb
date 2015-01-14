require_relative '../lib/net/tcp_client.rb'
require 'openssl'

p OpenSSL::SSL::SSLContext::DEFAULT_PARAMS
p OpenSSL::OPENSSL_VERSION
p RbConfig::CONFIG["configure_args"]
p OpenSSL::SSL::SSLContext::METHODS
p '-----'
p '**connecting...'
client = Net::TCPClient.new(
server:                 'localhost:1234',
connect_retry_interval: 0.1,
connect_retry_count:    5,
use_ssl:                true
)
p 'connected!'
p "#{client.use_ssl?}"
client.retry_on_connection_failure do
client.send('pewpew')
end

# Read upto 20 characters from the server
response = client.read_nonblock

puts "Received: #{response}"
client.close
