## Installation

Install all needed gems to run the tests:

    bundle update

## Run Tests

Run the tests:

    bundle exec rake

## Linux Testing

To perform Linux testing, for example when Travis fails, use docker to create run Linux locally:

    docker pull ruby

From the directory containing the source code run the following docker command:

    docker run -it --rm --volume `pwd`:/src ruby bash 

Docker should open a shell into which the following commands can be run:

    cd /src
    gem install bundler
    bundle update
    rake
