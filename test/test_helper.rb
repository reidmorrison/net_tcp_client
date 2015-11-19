# Allow test to be run in-place without requiring a gem install
$LOAD_PATH.unshift File.dirname(__FILE__) + '/../lib'

# Configure Rails Environment
ENV['RAILS_ENV'] = 'test'

require 'minitest/autorun'
require 'minitest/reporters'
require 'awesome_print'
begin
  require 'semantic_logger'
rescue LoadError
end

require 'net/tcp_client'

Minitest::Reporters.use! Minitest::Reporters::SpecReporter.new

if defined?(SemanticLogger)
  SemanticLogger.default_level = :trace
  SemanticLogger.add_appender('test.log', &SemanticLogger::Appender::Base.colorized_formatter)
end
