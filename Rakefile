require 'rake/testtask'
require_relative 'lib/net/tcp_client/version'

task :gem do
  system 'gem build net_tcp_client.gemspec'
end

task :publish => :gem do
  system "git tag -a v#{Net::TCPClient::VERSION} -m 'Tagging #{Net::TCPClient::VERSION}'"
  system 'git push --tags'
  system "gem push net_tcp_client-#{Net::TCPClient::VERSION}.gem"
  system "rm net_tcp_client-#{Net::TCPClient::VERSION}.gem"
end

Rake::TestTask.new(:test) do |t|
  t.pattern = 'test/**/*_test.rb'
  t.verbose = true
  t.warning = true
end

task :default => :test
