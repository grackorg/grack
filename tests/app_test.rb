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

class AppTest < Minitest::Test
  include Rack::Test::Methods
  include Grack

  def example_repo_urn
    '/example_repo.git'
  end

  def app_config
    {
      :root => repositories_root,
      :allow_pull => true,
      :allow_push => true,
      :git_adapter_factory => ->{ GitAdapter.new(git_path) }
    }
  end

  def app
    App.new(app_config)
  end

  def setup
    init_example_repository
  end

  def teardown
    remove_example_repository
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
    obj_path = 'objects/31/d73eb4914a8ddb6cb0e4adf250777161118f90'
    obj_file = File.join(example_repo, obj_path)
    content = File.open(obj_file, 'rb') { |f| f.read }

    get "#{example_repo_urn}/#{obj_path}"
    assert_equal 200, r.status
    assert_equal content, r.body
  end

  def test_pack_file
    pack_path =
      'objects/pack/pack-62c9f443d8405cd6da92dcbb4f849cc01a339c06.pack'
    pack_file = File.join(example_repo, pack_path)
    content = File.open(pack_file, 'rb') { |f| f.read }

    get "#{example_repo_urn}/#{pack_path}"
    assert_equal 200, r.status
    assert_equal content, r.body
  end

  def test_index_file
    idx_path = 'objects/pack/pack-62c9f443d8405cd6da92dcbb4f849cc01a339c06.idx'
    idx_file = File.join(example_repo, idx_path)
    content = File.open(idx_file, 'rb') { |f| f.read }

    get "#{example_repo_urn}/#{idx_path}"
    assert_equal 200, r.status
    assert_equal content, r.body
  end

  def test_text_file
    head_file = File.join(example_repo, 'HEAD')
    content = File.open(head_file, 'rb') { |f| f.read }

    get "#{example_repo_urn}/HEAD"
    assert_equal 200, r.status
    assert_equal content, r.body
  end

  def test_config_allow_pull_off
    session = Rack::Test::Session.new(
      App.new(app_config.merge(:allow_pull => false))
    )
    session.get "#{example_repo_urn}/info/refs?service=git-upload-pack"
    assert_equal 404, session.last_response.status
  end

  def test_config_allow_push_off
    session = Rack::Test::Session.new(
      App.new(app_config.merge(:allow_push => false))
    )
    session.get "#{example_repo_urn}/info/refs?service=git-receive-pack"
    assert_equal 404, session.last_response.status
  end

  def test_config_bad_service
    get "#{example_repo_urn}/info/refs?service=git-receive-packfile"
    assert_equal 404, r.status
  end

  def test_git_adapter_forbid_push
    GitAdapter.any_instance.stubs(:allow_push?).returns(false)

    app = App.new({
      :root => repositories_root
    })
    session = Rack::Test::Session.new(app)
    session.get "#{example_repo_urn}/info/refs?service=git-receive-pack"
    assert_equal 404, session.last_response.status
  end

  def test_git_adapter_allow_push
    GitAdapter.any_instance.stubs(:allow_push?).returns(true)

    app = App.new(:root => repositories_root)
    session = Rack::Test::Session.new(app)
    session.get "#{example_repo_urn}/info/refs?service=git-receive-pack"
    assert_equal 200, session.last_response.status
  end

  def test_git_adapter_forbid_pull
    GitAdapter.any_instance.stubs(:allow_pull?).returns(false)

    app = App.new(:root => repositories_root)
    session = Rack::Test::Session.new(app)
    session.get "#{example_repo_urn}/info/refs?service=git-upload-pack"
    assert_equal 404, session.last_response.status
  end

  def test_git_adapter_allow_pull
    GitAdapter.any_instance.stubs(:allow_pull?).returns(true)

    app = App.new(:root => repositories_root)
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
    empty_dir = repositories_root + 'empty-dir'
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

  def test_config_project_root_used_when_root_not_set
    session = Rack::Test::Session.new(
      App.new(:project_root => repositories_root)
    )

    session.get "#{example_repo_urn}/info/refs"
    assert_equal 200, session.last_response.status
  end

  def test_config_project_root_ignored_when_root_is_set
    session = Rack::Test::Session.new(
      App.new(:project_root => 'unlikely/path', :root => repositories_root)
    )

    session.get "#{example_repo_urn}/info/refs"
    assert_equal 200, session.last_response.status
  end

  def test_config_upload_pack_used_when_allow_pull_not_set
    session = Rack::Test::Session.new(
      App.new(:root => repositories_root, :upload_pack => false)
    )

    session.get "#{example_repo_urn}/info/refs?service=git-upload-pack"
    assert_equal 404, session.last_response.status
  end

  def test_config_upload_pack_ignored_when_allow_pull_is_set
    session = Rack::Test::Session.new(
      App.new(
        :root => repositories_root, :upload_pack => true, :allow_pull => false
      )
    )

    session.get "#{example_repo_urn}/info/refs?service=git-upload-pack"
    assert_equal 404, session.last_response.status
  end

  def test_config_receive_pack_used_when_allow_push_not_set
    session = Rack::Test::Session.new(
      App.new(:root => repositories_root, :receive_pack => false)
    )

    session.get "#{example_repo_urn}/info/refs?service=git-receive-pack"
    assert_equal 404, session.last_response.status
  end

  def test_config_receive_pack_ignored_when_allow_push_is_set
    session = Rack::Test::Session.new(
      App.new(
        :root => repositories_root, :receive_pack => true, :allow_push => false
      )
    )

    session.get "#{example_repo_urn}/info/refs?service=git-receive-pack"
    assert_equal 404, session.last_response.status
  end

  def test_config_adapter_with_GitAdapter
    session = Rack::Test::Session.new(
      App.new(:root => repositories_root, :adapter => GitAdapter)
    )

    session.get "#{example_repo_urn}/objects/info/packs"
    assert_equal 200, session.last_response.status
    assert_match /P pack-(.*?).pack/, session.last_response.body
  end

  def test_config_adapter_with_custom_adapter
    git_adapter = mock('git_adapter')
    git_adapter.
      expects(:update_server_info).
      with("#{repositories_root}#{example_repo_urn}")
    git_adapter_class = mock('git_adapter_class')
    git_adapter_class.expects(:new).with.returns(git_adapter)
    session = Rack::Test::Session.new(
      App.new(:root => repositories_root, :adapter => git_adapter_class)
    )

    session.get "#{example_repo_urn}/info/refs"
    assert_equal 200, session.last_response.status
  end

  def test_config_adapter_ignored_when_adapter_factory_is_set
    git_adapter_class = mock('git_adapter_class')
    session = Rack::Test::Session.new(
      App.new(
        :root => repositories_root,
        :adapter => git_adapter_class,
        :git_adapter_factory => ->{ GitAdapter.new(git_path) }
      )
    )

    session.get "#{example_repo_urn}/info/refs"
    assert_equal 200, session.last_response.status
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
