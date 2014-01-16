require 'memcached'
require 'action_dispatch/middleware/session/abstract_store'

module ActionDispatch
  module Session
    class LibmemcachedStore < AbstractStore

      def initialize(app, options = {})
        options[:expire_after] ||= options[:expires]
        super
        client_options = { :default_ttl => options.fetch(:expire_after, 0) }
        client_options[:prefix_key] = options[:prefix_key] || options[:namespace] || 'rack:session'
        @mutex = Mutex.new
        @pool = options[:cache] || Memcached.new(@default_options[:memcache_server], client_options)
      end

      private

      def generate_sid
        loop do
          sid = super
          begin
            @pool.exist(sid)
          rescue Memcached::NotFound
            break sid
          end
        end
      end

      def get_session(env, sid)
        sid ||= generate_sid
        session = with_lock(env, {}) do
          begin
            @pool.get(sid)
          rescue Memcached::NotFound
            {}
          end
        end
        [sid, session]
      end

      def set_session(env, session_id, new_session, options = {})
        expiry = options[:expire_after].to_i

        with_lock(env, false) do
          @pool.set(session_id, new_session, expiry)
          session_id
        end
      end

      def destroy_session(env, session_id, options = {})
        with_lock(env, nil) do
          @pool.delete(session_id)
          generate_sid unless options[:drop]
        end
      end

      #
      # Deprecated since Rails 3.1.0
      #
      def destroy(env)
        if sid = current_session_id(env)
          with_lock(env, false) do
            @pool.delete(sid)
          end
        end
      end

      def with_lock(env, default)
        @mutex.lock if env['rack.multithread']
        yield
      rescue Memcached::Error => e
        default
      ensure
        @mutex.unlock if @mutex.locked?
      end

    end
  end
end
