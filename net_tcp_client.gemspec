lib = File.expand_path("lib", __dir__)
$:.unshift lib unless $:.include?(lib)

# Gem's version:
require "net/tcp_client/version"

# Gem Declaration:
Gem::Specification.new do |spec|
  spec.name                  = "net_tcp_client"
  spec.version               = Net::TCPClient::VERSION
  spec.platform              = Gem::Platform::RUBY
  spec.authors               = ["Reid Morrison"]
  spec.homepage              = "https://github.com/reidmorrison/net_tcp_client"
  spec.summary               = "Net::TCPClient is a TCP Socket Client with built-in timeouts, retries, and logging"
  spec.description           = "Net::TCPClient implements resilience features that many developers wish was already included in the standard Ruby libraries."
  spec.files                 = Dir["lib/**/*", "LICENSE.txt", "Rakefile", "README.md"]
  spec.license               = "Apache-2.0"
  spec.required_ruby_version = ">= 2.3"
  spec.metadata["rubygems_mfa_required"] = "true"
end
