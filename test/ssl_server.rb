#!/usr/bin/ruby

require "socket"
require "openssl"
require "thread"

# listeningPort = Integer(ARGV[0])

server = TCPServer.new('0.0.0.0', '1234')

sslContext = OpenSSL::SSL::SSLContext.new
sslContext.ssl_version = :SSLv3
sslContext.cert = OpenSSL::X509::Certificate.new(IO.read("certificate.pem"))
sslContext.key = OpenSSL::PKey::RSA.new(File.open("private_key.pem"))
sslServer = OpenSSL::SSL::SSLServer.new(server, sslContext)

puts "Listening on port #{1234}"

loop do
    connection = sslServer.accept
    Thread.new {
      begin
        while (lineIn = connection.gets)
          lineIn = lineIn.chomp
          $stdout.puts "=> " + lineIn
          $stdout.puts "<= " + lineIn
          connection.puts lineIn
          connection.flush
        end
      rescue
        $stderr.puts $!
      end
    }
end
