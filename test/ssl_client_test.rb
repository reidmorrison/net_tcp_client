require 'socket'
require_relative 'test_helper'
require_relative 'simple_ssl_server'

# Unit Test for Net::SSLClient
module Net
  class SSLClientTest < Minitest::Test
    describe SSLClient do
      describe 'with imposter server' do
        before do
          @bad_server = SimpleSSLServer.new(
            2000,
            'badserver',
            ssl_file_path('google-server.pem'),
            ssl_file_path('google-server-key.pem'),
            ssl_file_path('ca.pem'))
          @bad_server_name = 'localhost:2000'
          @good_server = SimpleSSLServer.new(
            2001,
            'goodserver',
            ssl_file_path('localhost-server.pem'),
            ssl_file_path('localhost-server-key.pem'),
            ssl_file_path('ca.pem'))
          @good_server_name = 'localhost:2001'
        end

        after do
          @bad_server.stop if @bad_server
          @good_server.stop if @good_server
        end

        it 'connects to second server when the first is does not validate' do
          client = SSLClient.new(
            ssl_context_params: {
              ca_file: ssl_file_path('ca.pem')
            },
            servers:      [@bad_server_name, @good_server_name],
            read_timeout: 3
          )
          begin
            assert_equal @good_server_name, client.server

            request = {'action' => 'servername'}
              client.write(BSON.serialize(request))
            reply = read_bson_document(client)
            assert_equal 'goodserver', reply['result']
          ensure
            client.close
          end
        end
      end
    end
  end
end
