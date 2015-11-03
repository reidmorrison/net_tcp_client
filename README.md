# net_tcp_client
![](https://img.shields.io/gem/v/net_tcp_client.svg) ![](https://img.shields.io/travis/rocketjob/net_tcp_client.svg) ![](https://img.shields.io/gem/dt/net_tcp_client.svg) ![](https://img.shields.io/badge/status-production%20ready-blue.svg)

Net::TCPClient is a TCP Socket Client with built-in timeouts, retries, and logging

* http://github.com/rocketjob/net_tcp_client

## Introduction

Net::TCPClient implements resilience features that many developers wish was
already included in the standard Ruby libraries.

With so many "client" libraries to servers such us memcache, MongoDB, Redis, etc.
their focus is on the communication formats and messaging interactions. As a result
adding resilience is usually an after thought.

More importantly the way that each client implements connection failure handling
varies dramatically. The purpose of this library is to extract the best
of all the socket error handling out there and create a consistent way of dealing
with connection failures.

Another important feature is that the _connect_ and _read_ API's use timeout's to
prevent a network issue from "hanging" the client program.

## Net::TCPClient API

Net::TCPClient is a drop in replacement for TCPSocket when used as a client.

The initializer is the only deviation since it accepts several new options
that support automatic failover, re-connect and messaging retries.

## Example

Connect to a server at address `localhost`, and on port `3300`.

Specify a custom retry interval and retry counts during connection.

```ruby
require 'net/tcp_client'

Net::TCPClient.connect(
  server:                 'localhost:3300',
  connect_retry_interval: 0.1,
  connect_retry_count:    5
) do |client|
  # If the connection is lost, create a new one and retry the send
  client.retry_on_connection_failure do
    client.send('Update the database')
  end
  response = client.read(20)
  puts "Received: #{response}"
end
```

## Project Status

### Production Ready

Net::TCPClient is actively being used in a high performance, highly concurrent
production environments. The resilient capabilities of Net::TCPClient are put to the
test on a daily basis, including connections over the internet between remote data centers.

## Installation

    gem install net_tcp_client

Although not required, it is recommended to use [Semantic Logger](http://rocketjob.github.io/semantic_logger) for logging purposes:

    gem install semantic_logger

Or, add the following lines to you `Gemfile`:

```ruby
    gem 'semantic_logger'
    gem 'net_tcp_client'
```

To configure a stand-alone application for Semantic Logger:

```ruby
require 'semantic_logger'

# Set the global default log level
SemanticLogger.default_level = :trace

# Log to a file, and use the colorized formatter
SemanticLogger.add_appender('development.log', &SemanticLogger::Appender::Base.colorized_formatter)
```

If running rails, see: [Semantic Logger Rails](http://rocketjob.github.io/semantic_logger/rails.html)

Without SemanticLogger present a Ruby logger can be passed into Net::TCPClient.

### Upgrading from ResilientSocket

ResilientSocket::TCPClient has been renamed to Net::TCPClient.
The API is exactly the same, just with a new namespace. Please upgrade to the new
`net_tcp_client` gem and replace all occurrences of `ResilientSocket::TCPClient`
with `Net::TCPClient` in your code.

## Supports

Tested and supported on the following Ruby platforms:
- Ruby 1.9.3, 2.0, 2.1, 2.2 and above
- JRuby 1.7, 9.0 and above
- Rubinius 2.5 and above

There is a soft dependency on [Semantic Logger](http://github.com/rocketjob/semantic_logger). It will use SemanticLogger only if
it is already available, otherwise any other standard Ruby logger can be used.

### Note

Be sure to place the `semantic_logger` gem dependency before `net_tcp_client` in your Gemfile.

## Versioning

This project adheres to [Semantic Versioning](http://semver.org/).

## Author

[Reid Morrison](https://github.com/reidmorrison)

## Versioning

This project uses [Semantic Versioning](http://semver.org/).
