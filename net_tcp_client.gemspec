lib = File.expand_path('../lib/', __FILE__)
$:.unshift lib unless $:.include?(lib)

# Gem's version:
require 'net/tcp_client/version'

# Gem Declaration:
Gem::Specification.new do |spec|
  spec.name        = 'net_tcp_client'
  spec.version     = Net::TCPClient::VERSION
  spec.platform    = Gem::Platform::RUBY
  spec.authors     = ['Reid Morrison']
  spec.email       = ['reidmo@gmail.com']
  spec.homepage    = 'https://github.com/reidmorrison/net_tcp_client'
  spec.summary     = 'Net::TCPClient is a TCP Socket Client with built-in timeouts, retries, and logging'
  spec.description = 'Net::TCPClient implements resilience features that most developers wish was already included in the standard Ruby libraries.'
  spec.files       = Dir["lib/**/*", 'LICENSE.txt', 'Rakefile', 'README.md']
  spec.test_files  = Dir["test/**/*"]
  spec.license     = 'Apache License V2.0'
  spec.has_rdoc    = true
end
