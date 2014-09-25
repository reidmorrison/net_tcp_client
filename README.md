net_tcp_client
==============

Net::TCPClient is a TCP Socket Client with built-in timeouts, retries, and logging

* http://github.com/reidmorrison/net_tcp_client

### Upgrade Notice: ResilientSocket Renamed

ResilientSocket::TCPClient has been renamed to Net::TCPClient. The new gem name is
net_tcp_client.

The API is exactly the same, just with a new namespace. Please upgrade to the new
`net_tcp_client` gem and replace all occurrences of `ResilientSocket::TCPClient`
with `Net::TCPClient` in your code.

## Introduction

Net::TCPClient implements resilience features that most developers wish was
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

## Dependencies

- Ruby 1.9.3, JRuby 1.7, or greater

There is a soft dependency on SemanticLogger. It will use SemanticLogger only if
it is already available, otherwise any other standard Ruby logger can be used.
- [SemanticLogger](http://github.com/reidmorrison/semantic_logger)

## Production Use

Net::TCPClient was built for and is being used in a high performance, highly concurrent
production environment. The resilient capabilities of Net::TCPClient are put to the
test on a daily basis, especially with connections over the internet between
remote data centers.

## Installation

    gem install net_tcp_client

## Meta

* Code: `git clone git://github.com/reidmorrison/net_tcp_client.git`
* Home: <https://github.com/reidmorrison/net_tcp_client>
* Bugs: <http://github.com/reidmorrison/net_tcp_client/issues>
* Gems: <http://rubygems.org/gems/net_tcp_client>

This project uses [Semantic Versioning](http://semver.org/).

## Author

[Reid Morrison](https://github.com/reidmorrison) :: @reidmorrison

## License

Copyright 2012, 2013, 2014 Reid Morrison

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

    http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.
