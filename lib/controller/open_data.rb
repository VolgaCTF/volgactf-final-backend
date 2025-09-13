require 'json'
require 'redis'
require './lib/util/logger'

module VolgaCTF
  module Final
    module Controller
      class OpenData
        def initialize
          @_logger = ::VolgaCTF::Final::Util::Logger.get
          @_client = nil
        end

        def cache_open_data(key, val, ttl, expires, max_retries = 3)
          attempt = 0
          begin
            if attempt == max_retries
              @_logger.error "Failed to cache open data with key <#{key}>: #{val.to_json}"
              return
            end

            ensure_connection
            @_client.multi do
              @_client.setex(key, ttl, val.to_json)
              @_client.zadd("open_data", expires.to_time.to_i, key)
            end
          rescue ::Redis::CannotConnectError => e
            wait_period = 2**attempt
            attempt += 1
            @_logger.warn "#{e}, retrying in #{wait_period}s (attempt "\
                          "#{attempt})"
            sleep wait_period
            retry
          end
        end

        def cleanup_open_data_index(max_retries = 3)
          attempt = 0
          begin
            if attempt == max_retries
              @_logger.error "Failed to cleanup open data index"
              return
            end

            ensure_connection
            removed = @_client.zremrangebyscore("open_data", "-inf", ::Time.now.to_i)
            @_logger.info "Cleaned up #{removed} stale open data index entries"
          rescue ::Redis::CannotConnectError => e
            wait_period = 2**attempt
            attempt += 1
            @_logger.warn "#{e}, retrying in #{wait_period}s (attempt "\
                          "#{attempt})"
            sleep wait_period
            retry
          end
        end

        def fetch_open_data(max_retries = 3)
          attempt = 0
          begin
            if attempt == max_retries
              @_logger.error "Failed to fetch open data"
              return
            end

            ensure_connection
            keys = @_client.zrangebyscore("open_data", "(#{Time.now.to_i}", "+inf")
            entries = []
            unless keys.empty?
              values = @_client.mget(*keys)
              entries = values.map do |value|
                ::JSON.parse(value)
              end
            end

            entries
          rescue ::Redis::CannotConnectError => e
            wait_period = 2**attempt
            attempt += 1
            @_logger.warn "#{e}, retrying in #{wait_period}s (attempt "\
                          "#{attempt})"
            sleep wait_period
            retry
          end
        end

        protected
        def ensure_connection
          return unless @_client.nil?
          connection_params = {
            host: ::ENV['REDIS_HOST'] || '127.0.0.1',
            port: ::ENV['REDIS_PORT'].to_i || 6379,
            db: ::ENV['VOLGACTF_FINAL_OPEN_DATA_REDIS_DB'].to_i || 0
          }
          unless ::ENV.fetch('REDIS_PASSWORD', '').empty?
            connection_params[:password] = ::ENV['REDIS_PASSWORD']
          end
          @_client = ::Redis.new(**connection_params)
        end
      end
    end
  end
end
