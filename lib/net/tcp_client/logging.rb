module Net
  class TCPClient
    #
    # Purpose: Support SemanticLogger API without forcing a dependency on SemanticLogger
    #
    # This Mix-in has been copied from semantic_logger/compatible
    #
    # Do not modify this file, grab the latest version from Semantic Logger
    #
    module Logging
      def self.new_logger(logger=nil, name=nil, log_level=nil)
        # SemanticLogger is a soft dependency, use it if already loaded
        if defined?(SemanticLogger)
          SemanticLogger::Logger.new(name, log_level)
        elsif logger && !logger.respond_to?(:benchmark_trace)
          logger.extend(InstanceMethods)
          logger
        else
          # Return a nil logger
          require 'logger'
          logger       = Logger.new($null)
          logger.level = Logger::FATAL
          logger.extend(InstanceMethods)
          logger
        end
      end

      module InstanceMethods
        # See SemanticLogger for details on these logging extensions
        [:debug, :info, :warn, :error, :fatal].each_with_index do |level|
          class_eval <<-EOT, __FILE__, __LINE__ + 1
        def #{level}(message=nil, payload=nil, exception=nil, &block)
          if #{level}?
            super(format_log_message('#{level}', message, payload, exception, &block))
            true
          else
            false
          end
        end

        def benchmark_#{level}(message, params = {}, &block)
          if #{level}?
            benchmark(:#{level}, message, params, &block)
          else
            block.call(params) if block
          end
        end
          EOT
        end

        # Log trace level messages as debug
        def trace(*args)
          debug(*args)
        end

        def trace?
          debug?
        end

        def trace_benchmark(*args)
          debug_benchmark(*args)
        end

        def format_log_message(level, message=nil, payload=nil, exception=nil, duration=nil, &block)
          if exception.nil? && payload && payload.is_a?(Exception)
            exception = payload
            payload   = nil
          end

          if block && (result = block.call)
            if result.is_a?(String)
              message = message.nil? ? result : "\#{message} -- \#{result}"
            elsif payload && payload.respond_to?(:merge)
              payload.merge(result)
            else
              payload = result
            end
          end

          # Add scoped payload
          if self.payload
            payload = payload.nil? ? self.payload : self.payload.merge(payload)
          end

          tags_str = tags.collect { |tag| "[#{tag}]" }.join(" ") + " " if tags && (tags.size > 0)

          message = message.to_s.dup
          message << ' -- ' << payload.inspect if payload
          message << ' -- Exception: ' << "#{exception.class}: #{exception.message}\n#{(exception.backtrace || []).join("\n")}" if exception

          duration_str = duration ? "(#{'%.1f' % duration}ms) " : ''

          "#{tags_str}#{duration_str} #{message}"
        end

        # Measure the supplied block and log the message
        def benchmark(level, message, params, &block)
          start = Time.now
          begin
            rc        = block.call(params) if block
            exception = params[:exception]
            rc
          rescue Exception => exc
            exception = exc
          ensure
            end_time           = Time.now
            # Extract options after block completes so that block can modify any of the options
            log_exception      = params[:log_exception] || :partial
            on_exception_level = params[:on_exception_level]
            min_duration       = params[:min_duration] || 0.0
            payload            = params[:payload]
            metric             = params[:metric]
            duration           =
              if block_given?
                1000.0 * (end_time - start)
              else
                params[:duration] || raise('Mandatory block missing when :duration option is not supplied')
              end

            # Add scoped payload
            if self.payload
              payload = payload.nil? ? self.payload : self.payload.merge(payload)
            end
            if exception
              logged_exception = exception
              case log_exception
              when :full
                # On exception change the log level
                level = on_exception_level if on_exception_level
              when :partial
                # On exception change the log level
                level            = on_exception_level if on_exception_level
                message          = "#{message} -- Exception: #{exception.class}: #{exception.message}"
                logged_exception = nil
              else
                logged_exception = nil
              end
              send(level, format_log_message(level, message, payload, logged_exception, duration))
              raise exception
            elsif duration >= min_duration
              # Only log if the block took longer than 'min_duration' to complete
              send(level, format_log_message(level, message, payload, logged_exception, duration))
            end
          end
        end

        def tagged(*tags)
          new_tags = push_tags(*tags)
          yield self
        ensure
          pop_tags(new_tags.size)
        end

        # Previous method for supplying tags
        alias_method :with_tags, :tagged

        def tags
          # Since tags are stored on a per thread basis this list is thread-safe
          t = Thread.current[:semantic_logger_tags]
          t.nil? ? [] : t.clone
        end

        def push_tags *tags
          # Need to flatten and reject empties to support calls from Rails 4
          new_tags = tags.flatten.collect(&:to_s).reject(&:empty?)
          t        = Thread.current[:semantic_logger_tags]

          Thread.current[:semantic_logger_tags] = t.nil? ? new_tags : t.concat(new_tags)
          new_tags
        end

        def pop_tags(quantity=1)
          t = Thread.current[:semantic_logger_tags]
          t.pop(quantity) unless t.nil?
        end

        def with_payload(payload)
          current_payload                          = self.payload
          Thread.current[:semantic_logger_payload] = current_payload ? current_payload.merge(payload) : payload
          yield
        ensure
          Thread.current[:semantic_logger_payload] = current_payload
        end

        def payload
          Thread.current[:semantic_logger_payload]
        end

      end
    end
  end

end
