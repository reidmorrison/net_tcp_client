module ResilientSocket

  class Exception < ::RuntimeError; end
  class ConnectionTimeout < Exception; end
  class ReadTimeout < Exception; end
  class ConnectionFailure < Exception; end
  class ProtocolError < Exception; end
  class ServerError < Exception; end

end
