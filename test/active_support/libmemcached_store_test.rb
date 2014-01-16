require File.expand_path('../../test_helper', __FILE__)
require 'memcached'
require 'active_support'
require 'active_support/core_ext/module/aliasing'
require 'active_support/core_ext/object/duplicable'
require 'active_support/cache/libmemcached_store'

# Make it easier to get at the underlying cache options during testing.
ActiveSupport::Cache::LibmemcachedStore.class_eval do
  def client_options
    @cache.options
  end
end

describe ActiveSupport::Cache::LibmemcachedStore do
  class MockUser
    def cache_key
      'foo'
    end
  end

  before do
    @cache = ActiveSupport::Cache.lookup_store(:libmemcached_store, :expires_in => 60)
    @cache.clear
    @cache.silence!
  end

  describe "cache store behavior" do
    def really_long_keys_test
      key = "a" * 251
      assert @cache.write(key, "bar")
      assert_equal "bar", @cache.read(key)
      assert_equal "bar", @cache.fetch(key)
      assert_nil @cache.read("#{key}x")
      assert_equal({key => "bar"}, @cache.read_multi(key))
      assert @cache.delete(key)
      refute @cache.exist?(key)
      assert @cache.write(key, '2', :raw => true)
      assert_equal 3, @cache.increment(key)
      assert_equal 2, @cache.decrement(key)
    end

    it "fetch_without_cache_miss" do
      @cache.write('foo', 'bar')
      @cache.expects(:write_entry).never
      assert_equal 'bar', @cache.fetch('foo') { 'baz' }
    end

    it "fetch_with_cache_miss" do
      @cache.expects(:write_entry).with('foo', 'baz', nil)
      assert_equal 'baz', @cache.fetch('foo') { 'baz' }
    end

    it "fetch_with_forced_cache_miss" do
      @cache.write('foo', 'bar')
      @cache.expects(:read_entry).never
      @cache.expects(:write_entry).with('foo', 'baz', :force => true)
      assert_equal 'baz', @cache.fetch('foo', :force => true) { 'baz' }
    end

    it "fetch_with_cached_false" do
      @cache.write('foo', false)
      refute @cache.fetch('foo') { raise }
    end

    it "fetch_with_raw_object" do
      o = Object.new
      o.instance_variable_set :@foo, 'bar'
      assert_equal o, @cache.fetch('foo', :raw => true) { o }
    end

    it "fetch_with_cache_key" do
      u = MockUser.new
      @cache.write(u.cache_key, 'bar')
      assert_equal 'bar', @cache.fetch(u) { raise }
    end

    it "should_read_and_write_strings" do
      assert @cache.write('foo', 'bar')
      assert_equal 'bar', @cache.read('foo')
    end

    it "should_read_and_write_hash" do
      assert @cache.write('foo', { :a => 'b' })
      assert_equal({ :a => 'b' }, @cache.read('foo'))
    end

    it "should_read_and_write_integer" do
      assert @cache.write('foo', 1)
      assert_equal 1, @cache.read('foo')
    end

    it "should_read_and_write_nil" do
      assert @cache.write('foo', nil)
      assert_equal nil, @cache.read('foo')
    end

    it "should_read_and_write_false" do
      assert @cache.write('foo', false)
      assert_equal false, @cache.read('foo')
    end

    it "read_and_write_compressed_data" do
      @cache.write('foo', 'bar', :compress => true, :compress_threshold => 1)
      assert_equal 'bar', @cache.read('foo')
    end

    it "write_should_overwrite" do
      @cache.write('foo', 'bar')
      @cache.write('foo', 'baz')
      assert_equal 'baz', @cache.read('foo')
    end

    it "write_compressed_data" do
      @cache.write('foo', 'bar', :compress => true, :compress_threshold => 1, :raw => true)
      assert_equal Zlib::Deflate.deflate('bar'), @cache.instance_variable_get(:@cache).get('foo', false)
    end

    it "read_miss" do
      assert_nil @cache.read('foo')
    end

    it "read_should_return_a_different_object_id_each_time_it_is_called" do
      @cache.write('foo', 'bar')
      refute_equal @cache.read('foo').object_id, @cache.read('foo').object_id
    end

    it "read_multi" do
      @cache.write('foo', 'bar')
      @cache.write('fu', 'baz')
      @cache.write('fud', 'biz')
      assert_equal({"foo" => "bar", "fu" => "baz"}, @cache.read_multi('foo', 'fu'))
    end

    it "read_multi_with_array" do
      @cache.write('foo', 'bar')
      @cache.write('fu', 'baz')
      assert_equal({"foo" => "bar", "fu" => "baz"}, @cache.read_multi(['foo', 'fu']))
    end

    it "read_multi_with_raw" do
      @cache.write('foo', 'bar', :raw => true)
      @cache.write('fu', 'baz', :raw => true)
      assert_equal({"foo" => "bar", "fu" => "baz"}, @cache.read_multi('foo', 'fu'))
    end

    it "read_multi_with_compress" do
      @cache.write('foo', 'bar', :compress => true, :compress_threshold => 1)
      @cache.write('fu', 'baz', :compress => true, :compress_threshold => 1)
      assert_equal({"foo" => "bar", "fu" => "baz"}, @cache.read_multi('foo', 'fu'))
    end

    it "cache_key" do
      o = MockUser.new
      @cache.write(o, 'bar')
      assert_equal 'bar', @cache.read('foo')
    end

    it "param_as_cache_key" do
      obj = Object.new
      def obj.to_param
        'foo'
      end
      @cache.write(obj, 'bar')
      assert_equal 'bar', @cache.read('foo')
    end

    it "array_as_cache_key" do
      @cache.write([:fu, 'foo'], 'bar')
      assert_equal 'bar', @cache.read('fu/foo')
    end

    it "hash_as_cache_key" do
      @cache.write({:foo => 1, :fu => 2}, 'bar')
      assert_equal 'bar', @cache.read('foo=1/fu=2')
    end

    it "keys_are_case_sensitive" do
      @cache.write('foo', 'bar')
      assert_nil @cache.read('FOO')
    end

    it "keys_with_spaces" do
      assert_equal 'baz', @cache.fetch('foo bar') { 'baz' }
    end

    it "exist" do
      @cache.write('foo', 'bar')
      assert @cache.exist?('foo')
      refute @cache.exist?('bar')
    end

    it "delete" do
      @cache.write('foo', 'bar')
      assert @cache.exist?('foo')
      assert @cache.delete('foo')
      refute @cache.exist?('foo')
    end

    it "delete_with_unexistent_key" do
      @cache.expects(:log_error).never
      refute @cache.exist?('foo')
      refute @cache.delete('foo')
    end

    it "store_objects_should_be_immutable" do
      @cache.write('foo', 'bar')
      @cache.read('foo').gsub!(/.*/, 'baz')
      assert_equal 'bar', @cache.read('foo')
    end

    it "original_store_objects_should_not_be_immutable" do
      bar = 'bar'
      @cache.write('foo', bar)
      assert_equal 'baz', bar.gsub!(/r/, 'z')
    end

    it "crazy_key_characters" do
      crazy_key = "#/:*(<+=> )&$%@?;'\"\'`~-"
      assert @cache.write(crazy_key, "1", :raw => true)
      assert_equal "1", @cache.read(crazy_key)
      assert_equal "1", @cache.fetch(crazy_key)
      assert @cache.delete(crazy_key)
      refute @cache.exist?(crazy_key)
      assert_equal "2", @cache.fetch(crazy_key, :raw => true) { "2" }
      assert_equal 3, @cache.increment(crazy_key)
      assert_equal 2, @cache.decrement(crazy_key)
    end

    it "really_long_keys" do
      really_long_keys_test
    end

    it "really_long_keys_with_namespace" do
      @cache = ActiveSupport::Cache.lookup_store(:libmemcached_store, :expires_in => 60, :namespace => 'namespace')
      @cache.silence!
      really_long_keys_test
    end

    it "clear" do
      @cache.write("foo", "bar")
      @cache.clear
      assert_nil @cache.read("foo")
    end

    it "clear_with_options" do
      @cache.write("foo", "bar")
      @cache.clear(:some_option => true)
      assert_nil @cache.read("foo")
    end
  end

  describe "compression" do
    it "read_and_write_compressed_small_data" do
      @cache.write('foo', 'bar', :compress => true)
      raw_value = @cache.send(:read_entry, 'foo', {})
      assert_equal 'bar', @cache.read('foo')
      value = Marshal.load(raw_value) rescue raw_value
      assert_equal 'bar', value
    end

    it "read_and_write_compressed_large_data" do
      @cache.write('foo', 'bar', :compress => true, :compress_threshold => 2)
      raw_value = @cache.send(:read_entry, 'foo', :raw => true)
      assert_equal 'bar', @cache.read('foo')
      assert_equal 'bar', Marshal.load(raw_value)
    end
  end

  describe "increment / decrement" do
    it "increment" do
      @cache.write('foo', '1', :raw => true)
      assert_equal 1, @cache.read('foo').to_i
      assert_equal 2, @cache.increment('foo')
      assert_equal 2, @cache.read('foo').to_i
      assert_equal 3, @cache.increment('foo')
      assert_equal 3, @cache.read('foo').to_i
    end

    it "decrement" do
      @cache.write('foo', '3', :raw => true)
      assert_equal 3, @cache.read('foo').to_i
      assert_equal 2, @cache.decrement('foo')
      assert_equal 2, @cache.read('foo').to_i
      assert_equal 1, @cache.decrement('foo')
      assert_equal 1, @cache.read('foo').to_i
    end

    it "increment_decrement_non_existing_keys" do
      @cache.expects(:log_error).never
      assert_nil @cache.increment('foo')
      assert_nil @cache.decrement('bar')
    end
  end

  it "should_identify_cache_store" do
    assert_kind_of ActiveSupport::Cache::LibmemcachedStore, @cache
  end

  it "should_set_server_addresses_to_nil_if_none_are_given" do
    assert_equal [], @cache.addresses
  end

  it "should_set_custom_server_addresses" do
    store = ActiveSupport::Cache.lookup_store :libmemcached_store, 'localhost', '192.168.1.1'
    assert_equal %w(localhost 192.168.1.1), store.addresses
  end

  it "should_enable_consistent_ketema_hashing_by_default" do
    assert_equal :consistent_ketama, @cache.client_options[:distribution]
  end

  it "should_not_enable_non_blocking_io_by_default" do
    assert_equal false, @cache.client_options[:no_block]
  end

  it "should_not_enable_server_failover_by_default" do
    assert_nil @cache.client_options[:failover]
  end

  it "should_allow_configuration_of_custom_options" do
    options = { :client => { :tcp_nodelay => true, :distribution => :modula } }

    store = ActiveSupport::Cache.lookup_store :libmemcached_store, 'localhost', options

    assert_equal :modula, store.client_options[:distribution]
    assert_equal true, store.client_options[:tcp_nodelay]
  end

  it "should_allow_mute_and_silence" do
    cache = ActiveSupport::Cache.lookup_store :libmemcached_store, 'localhost'
    cache.mute do
      assert cache.write('foo', 'bar')
      assert_equal 'bar', cache.read('foo')
    end
    refute cache.silence?
    cache.silence!
    assert cache.silence?
  end

  describe "#fetch with :race_condition_ttl" do
    let(:options) { {:expires_in => 1, :race_condition_ttl => 5} }

    def fetch(&block)
      @cache.fetch("unknown", options, &block)
    end

    after do
      Thread.list.each { |t| t.exit unless t == Thread.current }
    end

    it "works like a normal fetch" do
      fetch { 1 }.must_equal 1
    end

    it "keeps a cached value even if the cache expires" do
      fetch { 1 } # fill it

      future = Time.now + 3 * 60
      Time.stubs(:now).returns future

      Thread.new do
        sleep 0.1
        fetch { raise }.must_equal 1 # 3rd fetch -> read expired value
      end
      fetch { sleep 0.2; 2 }.must_equal 2 # 2nd fetch -> takes time to generate but returns correct value
      fetch { 3 }.must_equal 2 # 4th fetch still correct value
    end

    it "can be read by a normal read" do
      fetch { 1 }
      @cache.read("unknown").must_equal 1
    end

    it "can be read by a normal fetch" do
      fetch { 1 }
      @cache.fetch("unknown") { 2 }.must_equal 1
    end

    it "can write to things that get fetched" do
      fetch { 1 }
      @cache.write "unknown", 2
      fetch { 1 }.must_equal 2
    end
  end
end
