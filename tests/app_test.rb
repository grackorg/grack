require_relative 'test_helper'

require 'digest/sha1'
require 'minitest/autorun'
require 'minitest/unit'
require 'mocha/setup'
require 'pathname'
require 'rack/test'
require 'tempfile'
require 'zlib'

require 'grack/app'
require 'grack/git_adapter'

class RequestHandlerTest < Minitest::Test
  include Rack::Test::Methods
  include Grack

  def example
    Pathname.new('../example').expand_path(__FILE__)
  end

  def example_repo_urn
    '/example_repo.git'
  end

  def app_config
    {
      :root => example,
      :allow_upload_pack => true,
      :allow_receive_pack => true,
      :adapter_factory => GitAdapterFactory.new(git_path)
    }
  end

  def app
    App.new(app_config)
  end

  def setup
    init_example_repository
  end

  def test_upload_pack_advertisement
    get "#{example_repo_urn}/info/refs?service=git-upload-pack"
    assert_equal 200, r.status
    assert_equal 'application/x-git-upload-pack-advertisement', r.headers['Content-Type']
    assert_equal '001e# service=git-upload-pack', r.body.split("\n").first
    assert_match 'multi_ack_detailed', r.body
  end

  def test_no_access_wrong_content_type_up
    post "#{example_repo_urn}/git-upload-pack"
    assert_equal 403, r.status
  end

  def test_no_access_wrong_content_type_rp
    post "#{example_repo_urn}/git-receive-pack"
    assert_equal 403, r.status
  end

  def test_no_access_wrong_method_rcp
    get "#{example_repo_urn}/git-upload-pack"
    assert_equal 400, r.status
    get "#{example_repo_urn}/git-upload-pack", {}, {'SERVER_PROTOCOL' => 'HTTP/1.1'}
    assert_equal 405, r.status
  end

  def test_no_access_wrong_command_rcp
    post "#{example_repo_urn}/git-upload-packfile"
    assert_equal 404, r.status
  end

  def test_no_access_wrong_path_rcp
    post "/example-wrong/git-upload-pack"
    assert_equal 404, r.status
  end

  def test_upload_pack_rpc
    IO.stubs(:popen).returns(MockProcess.new)
    post(
      "#{example_repo_urn}/git-upload-pack",
      {},
      {'CONTENT_TYPE' => 'application/x-git-upload-pack-request'}
    )
    assert_equal 200, r.status
    assert_equal 'application/x-git-upload-pack-result', r.headers['Content-Type']
  end

  def test_upload_pack_rpc_compressed
    IO.stubs(:popen).returns(MockProcess.new)

    content = StringIO.new
    gz = Zlib::GzipWriter.new(content)
    gz.write('foo')
    gz.close

    post(
      "#{example_repo_urn}/git-upload-pack",
      content.string,
      {
        'CONTENT_TYPE' => 'application/x-git-upload-pack-request',
        'HTTP_CONTENT_ENCODING' => 'gzip',
      }
    )
    assert_equal 200, r.status
    assert_equal 'application/x-git-upload-pack-result', r.headers['Content-Type']
  end

  def test_receive_pack_advertisement
    get "#{example_repo_urn}/info/refs?service=git-receive-pack"
    assert_equal 200, r.status
    assert_equal 'application/x-git-receive-pack-advertisement', r.headers['Content-Type']
    assert_equal '001f# service=git-receive-pack', r.body.split("\n").first
    assert_match 'report-status', r.body
    assert_match 'delete-refs', r.body
    assert_match 'ofs-delta', r.body
  end

  def test_recieve_pack_rpc
    IO.stubs(:popen).yields(MockProcess.new)
    post "#{example_repo_urn}/git-receive-pack", {}, {'CONTENT_TYPE' => 'application/x-git-receive-pack-request'}
    assert_equal 200, r.status
    assert_equal 'application/x-git-receive-pack-result', r.headers['Content-Type']
  end

  def test_info_refs_dumb
    get "#{example_repo_urn}/info/refs"
    assert_equal 200, r.status
  end

  def test_info_packs
    get "#{example_repo_urn}/objects/info/packs"
    assert_equal 200, r.status
    assert_match /P pack-(.*?).pack/, r.body
  end

  def test_loose_objects
    content = File.read(File.join(example_repo, '/objects/31/d73eb4914a8ddb6cb0e4adf250777161118f90')).force_encoding('binary')
    get "#{example_repo_urn}/objects/31/d73eb4914a8ddb6cb0e4adf250777161118f90"
    assert_equal 200, r.status
    assert_equal content, r.body
  end

  def test_pack_file
    content = File.read(File.join(example_repo, '/objects/pack/pack-62c9f443d8405cd6da92dcbb4f849cc01a339c06.pack')).force_encoding('binary')
    get "#{example_repo_urn}/objects/pack/pack-62c9f443d8405cd6da92dcbb4f849cc01a339c06.pack"
    assert_equal 200, r.status
    assert_equal content, r.body
  end

  def test_index_file
    content = File.read(File.join(example_repo, '/objects/pack/pack-62c9f443d8405cd6da92dcbb4f849cc01a339c06.idx')).force_encoding('binary')
    get "#{example_repo_urn}/objects/pack/pack-62c9f443d8405cd6da92dcbb4f849cc01a339c06.idx"
    assert_equal 200, r.status
    assert_equal content, r.body
  end

  def test_text_file
    get "#{example_repo_urn}/HEAD"
    assert_equal 200, r.status
    assert_equal 23, r.body.size
  end

  def test_no_size_avail
    File.stubs('size?').returns(false)
    get "#{example_repo_urn}/HEAD"
    assert_equal 200, r.status
    assert_equal 23, r.body.size
  end

  def test_config_upload_pack_off
    session = Rack::Test::Session.new(
      App.new(app_config.merge(:allow_upload_pack => false))
    )
    session.get "#{example_repo_urn}/info/refs?service=git-upload-pack"
    assert_equal 404, session.last_response.status
  end

  def test_config_receive_pack_off
    session = Rack::Test::Session.new(
      App.new(app_config.merge(:allow_receive_pack => false))
    )
    session.get "#{example_repo_urn}/info/refs?service=git-receive-pack"
    assert_equal 404, session.last_response.status
  end

  def test_config_bad_service
    get "#{example_repo_urn}/info/refs?service=git-receive-packfile"
    assert_equal 404, r.status
  end

  def test_git_adapter_forbid_receive_pack
    GitAdapter.any_instance.stubs(:allow_receive_pack?).returns(false)

    app = App.new({:root => example, :adapter_factory => GitAdapterFactory.new})
    session = Rack::Test::Session.new(app)
    session.get "#{example_repo_urn}/info/refs?service=git-receive-pack"
    assert_equal 404, session.last_response.status
  end

  def test_git_adapter_allow_receive_pack
    GitAdapter.any_instance.stubs(:allow_receive_pack?).returns(true)

    app = App.new({:root => example, :adapter_factory => GitAdapterFactory.new})
    session = Rack::Test::Session.new(app)
    session.get "#{example_repo_urn}/info/refs?service=git-receive-pack"
    assert_equal 200, session.last_response.status
  end

  def test_git_adapter_forbid_upload_pack
    GitAdapter.any_instance.stubs(:allow_upload_pack?).returns(false)

    app = App.new({:root => example, :adapter_factory => GitAdapterFactory.new})
    session = Rack::Test::Session.new(app)
    session.get "#{example_repo_urn}/info/refs?service=git-upload-pack"
    assert_equal 404, session.last_response.status
  end

  def test_git_adapter_allow_upload_pack
    GitAdapter.any_instance.stubs(:allow_upload_pack?).returns(true)

    app = App.new({:root => example, :adapter_factory => GitAdapterFactory.new})
    session = Rack::Test::Session.new(app)
    session.get "#{example_repo_urn}/info/refs?service=git-upload-pack"
    assert_equal 200, session.last_response.status
  end

  def test_reject_bad_uri
    get '/../HEAD'
    assert_equal 400, r.status
    get "#{example_repo_urn}/../HEAD"
    assert_equal 400, r.status
    get '/./HEAD'
    assert_equal 400, r.status
    get "#{example_repo_urn}/./HEAD"
    assert_equal 400, r.status

    get '/%2e%2e/HEAD'
    assert_equal 400, r.status
    get "#{example_repo_urn}/%2e%2e/HEAD"
    assert_equal 400, r.status
    get '/%2e/HEAD'
    assert_equal 400, r.status
    get "#{example_repo_urn}/%2e/HEAD"
    assert_equal 400, r.status
  end

  def test_not_found_in_empty_repo
    empty_dir = example + 'empty-dir'
    empty_dir.mkdir

    example_repo_urn = '/empty-dir'

    get "#{example_repo_urn}/info/refs"
    assert_equal 404, r.status
    get "#{example_repo_urn}/info/alternates"
    assert_equal 404, r.status
    get "#{example_repo_urn}/info/http-alternates"
    assert_equal 404, r.status
    get "#{example_repo_urn}/info/packs"
    assert_equal 404, r.status
    get "#{example_repo_urn}/objects/00/00000000000000000000000000000000000000"
    assert_equal 404, r.status
    get "#{example_repo_urn}/objects/packs/pack-0000000000000000000000000000000000000000.pack"
    assert_equal 404, r.status
    get "#{example_repo_urn}/objects/packs/pack-0000000000000000000000000000000000000000.idx"
    assert_equal 404, r.status
  ensure
    empty_dir.rmdir if empty_dir.exist?
  end

  def test_not_found_in_nonexistent_repo
    example_repo_urn = '/no-dir'

    get "#{example_repo_urn}/info/refs"
    assert_equal 404, r.status
    get "#{example_repo_urn}/info/alternates"
    assert_equal 404, r.status
    get "#{example_repo_urn}/info/http-alternates"
    assert_equal 404, r.status
    get "#{example_repo_urn}/info/packs"
    assert_equal 404, r.status
    get "#{example_repo_urn}/objects/00/00000000000000000000000000000000000000"
    assert_equal 404, r.status
    get "#{example_repo_urn}/objects/packs/pack-0000000000000000000000000000000000000000.pack"
    assert_equal 404, r.status
    get "#{example_repo_urn}/objects/packs/pack-0000000000000000000000000000000000000000.idx"
    assert_equal 404, r.status
  end

  private

  def r
    last_response
  end

end

class MockProcess

  def initialize
    @counter = 0
  end

  def close_write
  end

  def write(data)
  end

  def read(length = nil, buffer = nil)
    nil
  end

end
