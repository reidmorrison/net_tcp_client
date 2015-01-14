#!/usr/bin/ruby

require "socket"
require "openssl"
require "thread"

# listeningPort = Integer(ARGV[0])


server = TCPServer.new('0.0.0.0', '1234')

sslContext = OpenSSL::SSL::SSLContext.new
# sslContext.ssl_version = :SSLv23
sslContext.ssl_version = :TLSv1
sslContext.cert = OpenSSL::X509::Certificate.new(File.open("localhost.pem"))
sslContext.key = OpenSSL::PKey::RSA.new(File.open("private.key"))
sslServer = OpenSSL::SSL::SSLServer.new(server, sslContext)

puts "Listening on port #{1234}"

p OpenSSL::SSL::SSLContext::DEFAULT_PARAMS
p OpenSSL::OPENSSL_VERSION
p RbConfig::CONFIG["configure_args"]
p OpenSSL::SSL::SSLContext::METHODS
p '--------'
loop do

    connection = sslServer.accept
    Thread.new {
      begin
        while (lineIn = connection.gets)
          lineIn = lineIn.chomp
          $stdout.puts "=> " + lineIn
          lineOut = "You said: " + lineIn
          $stdout.puts "<= " + lineOut
          connection.puts lineOut
        end
      rescue
        $stderr.puts $!
      end
    }

end
