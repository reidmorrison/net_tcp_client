# Allow test to be run in-place without requiring a gem install
$LOAD_PATH.unshift "#{File.dirname(__FILE__)}/../lib"

# Configure Rails Environment
ENV["RAILS_ENV"] = "test"

require "minitest/autorun"
require "timeout"
require "minitest/reporters"
require "net/tcp_client"
require "amazing_print"

SemanticLogger.default_level = :trace
SemanticLogger.add_appender(file_name: "test.log", formatter: :color)

# Fail a test that hangs, instead of hanging the whole run.
# Set TEST_TIMEOUT to the number of seconds a test may take. Default: 60
module TestTimeout
  # Not a StandardError, so that code under test that rescues StandardError cannot hide it.
  class Expired < Exception # rubocop:disable Lint/InheritException
  end

  LIMIT = Float(ENV.fetch("TEST_TIMEOUT", 60))

  # Minitest runs the setup and the test inside one #capture_exceptions block, and each teardown
  # in another, then records what they raise. Expired is raised inside the block, so a test that
  # runs too long is recorded as an error, and its teardown still runs.
  def capture_exceptions(&block)
    super { Timeout.timeout(LIMIT, Expired, "Did not finish within #{LIMIT} seconds", &block) }
  end
end
Minitest::Test.prepend(TestTimeout)

reporters = [
  Minitest::Reporters::SpecReporter.new
  # SemanticLogger::Reporters::Minitest.new
]
Minitest::Reporters.use!(reporters)
