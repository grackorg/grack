require_relative 'test_helper'

require 'fileutils'
require 'minitest/autorun'
require 'minitest/unit'
require 'mocha/setup'
require 'stringio'

require 'grack/git_adapter'


class GitAdapterTest < Minitest::Test
  include Grack

  GIT_RECEIVE_RESPONSE = %r{\A001b# service=receive-pack\n0000[0-9a-f]{4}cb067e06bdf6e34d4abebf6cf2de85d65a52c65e refs/heads/master\000\s*report-status delete-refs side-band-64k quiet ofs-delta.*\n0000\z}

  def git_config_set(name, value)
    system(git_path, 'config', '--local', name, value, :chdir => example_repo)
  end

  def git_config_unset(name)
    system(
      git_path, 'config', '--local', '--unset-all', name, :chdir => example_repo
    )
  end

  def setup
    init_example_repository
    @test_git = GitAdapter.new(git_path)
    @test_git.repository_path = example_repo
  end

  def teardown
    remove_example_repository
  end

  def test_break_with_bad_git_path
    test_git = GitAdapter.new('a/highly/unlikely/path/to/git')
    test_git.repository_path = example_repo
    assert_raises(Errno::ENOENT) do
      test_git.handle_pack('receive-pack', StringIO.new, StringIO.new)
    end
  end

  def test_receive_pack
    output = StringIO.new
    @test_git.handle_pack(
      'receive-pack', StringIO.new, output, :advertise_refs => true
    )

    assert_match GIT_RECEIVE_RESPONSE, output.string
  end

  def test_upload_pack
    input = StringIO.new('0000')
    output = StringIO.new
    @test_git.handle_pack('upload-pack', input, output)

    assert_equal '', output.string
  end

  def test_update_server_info
    refs_file = File.join(example_repo, 'info/refs')
    refs = File.read(refs_file)
    File.unlink(refs_file)
    assert ! File.exist?(refs_file), 'refs file exists'
    @test_git.update_server_info
    assert_equal refs, File.read(refs_file)
  end

  def test_exist
    assert @test_git.exist?
    @test_git.repository_path = 'a/highly/unlikely/path/to/a/repository'
    assert ! @test_git.exist?
  end

  def test_file
    assert_nil @test_git.file('a/highly/unlikely/path/to/a/file')

    object_path = 'objects/31/d73eb4914a8ddb6cb0e4adf250777161118f90'
    file_path = File.join(example_repo, object_path)
    git_file = @test_git.file(object_path)

    assert_equal file_path, git_file.to_path.to_s
    assert_equal File.mtime(file_path), git_file.mtime
  end

  def test_allow_push
    assert ! @test_git.allow_push?, 'Expected allow_push? to return false'
    git_config_set('http.receivepack', 'false')
    assert ! @test_git.allow_push?, 'Expected allow_push? to return false'
    git_config_set('http.receivepack', 'true')
    assert @test_git.allow_push?, 'Expected allow_push? to return true'
  end

  def test_allow_pull
    assert @test_git.allow_pull?, 'Expected allow_pull? to return true'
    git_config_set('http.uploadpack', 'false')
    assert ! @test_git.allow_pull?, 'Expected allow_pull? to return false'
    git_config_set('http.uploadpack', 'true')
    assert @test_git.allow_pull?, 'Expected allow_pull? to return true'
  end

end
