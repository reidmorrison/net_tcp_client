# net_tcp_client
[![Gem Version](https://img.shields.io/gem/v/net_tcp_client.svg)](https://rubygems.org/gems/net_tcp_client) [![Build Status](https://travis-ci.org/rocketjob/net_tcp_client.svg?branch=master)](https://travis-ci.org/rocketjob/net_tcp_client) [![Downloads](https://img.shields.io/gem/dt/net_tcp_client.svg)](https://rubygems.org/gems/net_tcp_client) [![License](https://img.shields.io/badge/license-Apache%202.0-brightgreen.svg)](http://opensource.org/licenses/Apache-2.0) ![](https://img.shields.io/badge/status-Production%20Ready-blue.svg) [![Gitter chat](https://img.shields.io/badge/IRC%20(gitter)-Support-brightgreen.svg)](https://gitter.im/rocketjob/support)

Net::TCPClient is a TCP Socket Client with automated failover, load balancing, retries and built-in timeouts.

* http://github.com/rocketjob/net_tcp_client

## Introduction

Net::TCPClient implements high availability and resilience features that many developers wish was
already included in the standard Ruby libraries.

Another important feature is that the _connect_ and _read_ API's use timeout's to
prevent a network issue from "hanging" the client program.

## Features

* Automated failover to another server.
* Load balancing across multiple servers.
* SSL and non-ssl connections.
* Connect Timeout.
* Read Timeout.
* Write Timeout.
* Fails over / load balances across all servers under a single DNS entry.
* Logging.
    * Optional trace level logging of all data sent or received.
* Uses non blocking timeouts, instead of using threads such as used by the Timeout class.
* Additional exceptions to distinguish between connection failures and timeouts.
* Handshake callbacks.
    * After a new connection has been established callbacks can be used
      for handshakes such as authentication before data is sent.

### Example

~~~ruby
require 'net/tcp_client'

Net::TCPClient.connect(server: 'mydomain:3300') do |client|
  client.send('Update the database')
  response = client.read(20)
  puts "Received: #{response}"
end
~~~

Enable SSL encryption:

~~~ruby
require 'net/tcp_client'

Net::TCPClient.connect(server: 'mydomain:3300', ssl: true) do |client|
  client.send('Update the database')
  response = client.read(20)
  puts "Received: #{response}"
end
~~~

## High Availability

Net::TCPClient automatically tries each server in turn, should it fail to connect, or
if the connection is lost the next server is tried immediately.

Net::TCPClient detects DNS entries that have multiple IP Addresses associated with them and
adds each of the ip addresses for the single DNS name to the list of servers to try to connect to.

If a server is unavailable, cannot connect, or the connection is lost, the next server is immediately
tried. Once all servers have been exhausted, it will keep trying to connect, starting with the
first server again.

When a connection is first established, and every time a connection is lost, Net::TCPClient
uses connection policies to determine which server to connect to.

## Load Balancing

Using the connection policies client TCP connections can be balanced across multiple servers.

## Connection Policies

#### Ordered

Servers are tried in the order they were supplied.

~~~ruby
tcp_client = Net::TCPClient.new(
  servers: ['server1:3300', 'server2:3300', 'server3:3600']
)
~~~

The servers will tried in the following order:
`server1`, `server2`, `server3`

`:ordered` is the default, but can be explicitly defined follows:

~~~ruby
tcp_client = Net::TCPClient.new(
  servers: ['server1:3300', 'server2:3300', 'server3:3600'],
  policy:  :ordered
)
~~~

#### Random

Servers are tried in a Random order.

~~~ruby
tcp_client = Net::TCPClient.new(
  servers: ['server1:3300', 'server2:3300', 'server3:3600'],
  policy:  :ordered
)
~~~

No server is tried again until all of the others have been tried first.

Example run, the servers could be tried in the following order:
`server3`, `server1`, `server2`

#### Custom defined order

Supply your own custom order / load balancing algorithm for connecting to servers:

Example:

~~~ruby
tcp_client = Net::TCPClient.new(
  servers: ['server1:3300', 'server2:3300', 'server3:3600'],
  policy:  -> addresses, count do
    # Return nil after the last address has been tried so that retry logic can take over
    if count <= address.size
      addresses.sample
    end
  end
)
~~~

The above example returns addresses in random order without checking if a host name has been used before.

It is important to check the count so that once all servers have been tried, it should return nil so that
the retry logic can take over. Otherwise it will constantly try to connect to the servers without
the retry delays etc.

Example run, the servers could be tried in the following order:
`server3`, `server1`, `server3`

### Automatic Retry

If a connection cannot be established to any servers in the list Net::TCPClient will retry from the
first server. This retry behavior can be controlled using the following options:

* `connect_retry_count` [Fixnum]
    * Number of times to retry connecting when a connection fails
    * Default: 10

* `connect_retry_interval` [Float]
    * Number of seconds between connection retry attempts after the first failed attempt
    * Default: 0.5

* `retry_count` [Fixnum]
    * Number of times to retry when calling #retry_on_connection_failure
    * This is independent of :connect_retry_count which still applies with
    * connection failures. This retry controls upto how many times to retry the
    * supplied block should a connection failure occur during the block
    * Default: 3

#### Note

A server will only be retried again using the retry controls above once all other servers in the
list have been exhausted.

This means that if a connection is lost to a server that it will try to connect to a different server,
not the same server unless it is the only server in the list.

## Tuning

If there are multiple servers in the list it is important to keep the `connect_timeout` low otherwise
it can take a long time to find the next available server.

## Retry on connection loss

To transparently handle when a connection is lost after it has been established
wrap calls that can be retried with `retry_on_connection_failure`.

~~~ruby
Net::TCPClient.connect(
  server:                 'localhost:3300',
  connect_retry_interval: 0.1,
  connect_retry_count:    5
) do |client|
  # If the connection is lost, create a new one and retry the send
  client.retry_on_connection_failure do
    client.send('How many users available?')
    response = client.read(20)
    puts "Received: #{response}"
  end
end
~~~

If the connection is lost during either the `send` or the `read` above the
entire block will be re-tried once the connection has been re-stablished.

## Callbacks

Any time a connection has been established a callback can be called to handle activities such as:

* Initialize per connection session sequence numbers.
* Pass authentication information to the server.
* Perform a handshake with the server.

#### Authentication example:

~~~ruby
tcp_client = Net::TCPClient.new(
  servers: ['server1:3300', 'server2:3300', 'server3:3600'],
  on_connect: -> do |client|
    client.send('My username and password')
    result = client.read(2)
    raise "Authentication failed" if result != 'OK'
  end
)
~~~

#### Per connection sequence number example:

~~~ruby
tcp_client = Net::TCPClient.new(
  servers: ['server1:3300', 'server2:3300', 'server3:3600'],
  on_connect: -> do |client|
    # Set the sequence number to 0
    user_data = 0
  end
)

tcp_client.retry_on_connection_failure do
  # Send with the sequence number
  tcp_client.send("#{tcp_client.user_data} hello")
  result = tcp_client.receive(30)

  # Increment sequence number after every call to the server
  tcp_client.user_data += 1
end
~~~

## Project Status

### Production Ready

Net::TCPClient is actively being used in a high performance, highly concurrent
production environments. The resilient capabilities of Net::TCPClient are put to the
test on a daily basis, including connections over the internet between remote data centers.

## Installation

    gem install net_tcp_client

To enable logging add [Semantic Logger](http://rocketjob.github.io/semantic_logger):

    gem install semantic_logger

Or, add the following lines to you `Gemfile`:

~~~ruby
gem 'semantic_logger'
gem 'net_tcp_client'
~~~

To configure a stand-alone application for Semantic Logger:

~~~ruby
require 'semantic_logger'

# Set the global default log level
SemanticLogger.default_level = :trace

# Log to a file, and use the colorized formatter
SemanticLogger.add_appender(file_name: 'development.log', formatter: :color)
~~~

If running Rails, see: [Semantic Logger Rails](http://rocketjob.github.io/semantic_logger/rails.html)

### Support

Join the [Gitter chat session](https://gitter.im/rocketjob/support) if you have any questions.

Issues / bugs can be reported via [Github issues](https://github.com/rocketjob/net_tcp_client/issues).

### Upgrading to V2

The following breaking changes have been made with V2:
* The Connection timeout default is now 10 seconds, was 30 seconds.
* To enable logging, add gem semantic_logger.
    * The :logger option has been removed.
* Deprecated option and attribute :server_selector has been removed.

### Upgrading from ResilientSocket ![](https://img.shields.io/gem/dt/resilient_socket.svg)

ResilientSocket::TCPClient has been renamed to Net::TCPClient.
The API is exactly the same, just with a new namespace. Please upgrade to the new
`net_tcp_client` gem and replace all occurrences of `ResilientSocket::TCPClient`
with `Net::TCPClient` in your code.

## Supports

Tested and supported on the following Ruby platforms:
- Ruby 2.1, 2.2, 2.3 and above
- JRuby 1.7.23, 9.0 and above
- Rubinius 2.5 and above

There is a soft dependency on [Semantic Logger](http://github.com/rocketjob/semantic_logger). It will use SemanticLogger only if
it is already available, otherwise any other standard Ruby logger can be used.

### Note

Be sure to place the `semantic_logger` gem dependency before `net_tcp_client` in your Gemfile.

## Author

[Reid Morrison](https://github.com/reidmorrison)

[Contributors](https://github.com/rocketjob/net_tcp_client/graphs/contributors)

## Versioning

This project uses [Semantic Versioning](http://semver.org/).
