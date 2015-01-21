#!/usr/bin/env ruby
require 'openssl'

key = OpenSSL::PKey::RSA.new 2048
open('private_key.pem', 'w') {|io| io.write key.to_pem }
open('public_key.pem', 'w') {|io| io.write key.public_key.to_pem }

# Create cert
name = OpenSSL::X509::Name.parse("CN=blahtesting/DC=woo/DC=com")
cert = OpenSSL::X509::Certificate.new()
cert.version = 2
cert.serial = 0
cert.not_before = Time.new()
cert.not_after = cert.not_before + (60*60*24*365)
puts "cert.not_before=#{cert.not_before}"
puts "cert.not_after=#{cert.not_after}"
cert.public_key = key.public_key
cert.subject = name

# Sign cert
cert.issuer = name
cert.sign key, OpenSSL::Digest::SHA1.new()
open("certificate.pem", "w") do |io| io.write(cert.to_pem) end
