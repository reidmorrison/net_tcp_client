# Allow test to be run in-place without requiring a gem install
$LOAD_PATH.unshift File.dirname(__FILE__) + '/../lib'

# Configure Rails Environment
ENV['RAILS_ENV'] = 'test'

require 'minitest/autorun'
require 'minitest/reporters'
require 'semantic_logger'
require 'net/tcp_client'

Minitest::Reporters.use! Minitest::Reporters::SpecReporter.new

SemanticLogger.default_level = :trace
SemanticLogger.add_appender('test.log')

