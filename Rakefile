lib = File.expand_path('../lib/', __FILE__)
$:.unshift lib unless $:.include?(lib)

require 'rubygems'
require 'rake/clean'
require 'rake/testtask'
require 'date'
require 'resilient_socket/version'

desc "Build gem"
task :gem  do |t|
  gemspec = Gem::Specification.new do |spec|
    spec.name        = 'resilient_socket'
    spec.version     = ResilientSocket::VERSION
    spec.platform    = Gem::Platform::RUBY
    spec.authors     = ['Reid Morrison']
    spec.email       = ['reidmo@gmail.com']
    spec.homepage    = 'https://github.com/ClarityServices/resilient_socket'
    spec.date        = Date.today.to_s
    spec.summary     = "A Resilient TCP Socket Client with built-in timeouts, retries, and logging"
    spec.description = "A Resilient TCP Socket Client with built-in timeouts, retries, and logging"
    spec.files       = FileList["./**/*"].exclude('*.gem', 'nbproject').map{|f| f.sub(/^\.\//, '')}
    spec.has_rdoc    = true
    spec.add_dependency 'semantic_logger'
  end
  Gem::Builder.new(gemspec).build
end

desc "Run Test Suite"
task :test do
  Rake::TestTask.new(:functional) do |t|
    t.test_files = FileList['test/*_test.rb']
    t.verbose    = true
  end

  Rake::Task['functional'].invoke
end
