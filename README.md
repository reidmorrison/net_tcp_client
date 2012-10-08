resilient_socket
================

A Resilient TCP Socket Client with built-in timeouts, retries, and logging

* http://github.com/ClarityServices/resilient_socket

### Introduction

Resilient Socket implements resilience features that most developers wish was
already included in the standard Ruby libraries.

With so many "client" libraries to servers such us memcache, MongoDB, Redis, etc.
their focus on the communication formats and messaging interactions. As a result
adding resilience is usually an after thought.

More importantly the way that each client implements connection failure handling
varies dramatically. The purpose of this library is to try and extract the best
of all the socket error handling out there and create a consistent way of dealing
with connection failures.

Another important feature is that the _connect_ and _read_ API's use timeout's to
prevent a network issue from "hanging" the client program.

It is expected that this library will undergo significant changes until V1 is reached
as input is gathered from client library developers. After V1 the interface should
not break existing users

### TCPClient API

#### Standard Logging methods

TCPClient should be a drop in replacement for TCPSocket when used as a client
in any way needed other than for the initializer that accepts several new options
to adjust the retry logic

### Dependencies

- Ruby MRI 1.8.7 (or above), Ruby 1.9.3,  Or JRuby 1.6.3 (or above)
- [SemanticLogger](http://github.com/ClarityServices/semantic-logger)

### Install

    gem install resilient_socket

### Future

- Look into using https://github.com/tarcieri/nio4r for Async IO

Development
-----------

Want to contribute to Resilient Socket?

First clone the repo and run the tests:

    git clone git://github.com/ClarityServices/resilient_socket.git
    cd resilient_socket
    jruby -S rake test

Feel free to ping the mailing list with any issues and we'll try to resolve it.

Contributing
------------

Once you've made your great commits:

1. [Fork](http://help.github.com/forking/) resilient_socket
2. Create a topic branch - `git checkout -b my_branch`
3. Push to your branch - `git push origin my_branch`
4. Create an [Issue](http://github.com/ClarityServices/resilient_socket/issues) with a link to your branch
5. That's it!

Meta
----

* Code: `git clone git://github.com/ClarityServices/resilient_socket.git`
* Home: <https://github.com/ClarityServices/resilient_socket>
* Bugs: <http://github.com/reidmorrison/resilient_socket/issues>
* Gems: <http://rubygems.org/gems/resilient_socket>

This project uses [Semantic Versioning](http://semver.org/).

Authors
-------

Reid Morrison :: reidmo@gmail.com :: @reidmorrison

License
-------

Copyright 2012 Clarity Services, Inc.

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

    http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.
