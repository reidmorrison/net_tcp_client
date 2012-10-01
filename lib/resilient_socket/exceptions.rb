module ResilientSocket

  class Exception < ::RuntimeError; end
  class ConnectionTimeout < Exception; end
  class ReadTimeout < Exception; end
  class ConnectionFailure < Exception; end

end
