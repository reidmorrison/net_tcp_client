require 'rake/clean'
require 'rake/testtask'

$LOAD_PATH.unshift File.expand_path("../lib", __FILE__)
require 'net/tcp_client/version'

task :gem do
  system 'gem build net_tcp_client.gemspec'
end

task :publish => :gem do
  system "git tag -a v#{Net::TCPClient::VERSION} -m 'Tagging #{Net::TCPClient::VERSION}'"
  system 'git push --tags'
  system "gem push net_tcp_client-#{Net::TCPClient::VERSION}.gem"
  system "rm net_tcp_client-#{Net::TCPClient::VERSION}.gem"
end

desc 'Run Test Suite'
task :test do
  Rake::TestTask.new(:functional) do |t|
    t.test_files = FileList['test/*_test.rb']
    t.verbose    = true
  end

  Rake::Task['functional'].invoke
end

task :default => :test
