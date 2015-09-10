require_relative 'test_helper'

require 'minitest/autorun'
require 'minitest/unit'
require 'mocha/setup'
require 'pathname'
require 'stringio'

require 'grack/compatible_git_adapter'

class CompatibleGitAdapterTest < Minitest::Test
  include Grack

  def test_receive_pack
    mock_adapter = mock('git_adapter')
    mock_adapter.
      expects(:receive_pack).
      with('repo/path', :advertise_refs => true, :msg => '').
      yields(StringIO.new('results'))
    test_git = CompatibleGitAdapter.new(mock_adapter)
    test_git.repository_path = Pathname.new('repo/path')

    output = StringIO.new
    test_git.handle_pack(
      'receive-pack', StringIO.new, output, :advertise_refs => true
    )

    assert_match 'results', output.string
  end

  def test_upload_pack
    mock_adapter = mock('git_adapter')
    mock_adapter.
      expects(:upload_pack).
      with('repo/path', :msg => 'input').
      yields(StringIO.new('results'))
    test_git = CompatibleGitAdapter.new(mock_adapter)
    test_git.repository_path = Pathname.new('repo/path')

    output = StringIO.new
    test_git.handle_pack('upload-pack', StringIO.new('input'), output)

    assert_match 'results', output.string
  end

  def test_update_server_info
    mock_adapter = mock('git_adapter')
    mock_adapter.expects(:update_server_info).with('repo/path').returns(nil)
    test_git = CompatibleGitAdapter.new(mock_adapter)
    test_git.repository_path = Pathname.new('repo/path')

    test_git.update_server_info
  end

  def test_exist
    test_git = CompatibleGitAdapter.new(nil)
    test_git.repository_path = Dir.pwd
    assert test_git.exist?
    test_git.repository_path = 'a/highly/unlikely/path/to/a/repository'
    assert ! test_git.exist?
  end

  def test_file
    init_example_repository
    test_git = CompatibleGitAdapter.new(nil)
    test_git.repository_path = example_repo

    assert_nil test_git.file('a/highly/unlikely/path/to/a/file')

    object_path = 'objects/31/d73eb4914a8ddb6cb0e4adf250777161118f90'
    file_path = File.join(example_repo, object_path)
    git_file = test_git.file(object_path)

    assert_equal file_path, git_file.to_path.to_s
    assert_equal File.mtime(file_path), git_file.mtime
  ensure
    remove_example_repository
  end

  def test_allow_push_with_true_setting
    mock_adapter = mock('git_adapter')
    mock_adapter.
      expects(:get_config_setting).
      with('receivepack').
      returns('true')
    test_git = CompatibleGitAdapter.new(mock_adapter)

    assert test_git.allow_push?, 'Expected allow_push? to return true'
  end

  def test_allow_push_with_false_setting
    mock_adapter = mock('git_adapter')
    mock_adapter.
      expects(:get_config_setting).
      with('receivepack').
      returns('false')
    test_git = CompatibleGitAdapter.new(mock_adapter)

    assert ! test_git.allow_push?, 'Expected allow_push? to return false'
  end

  def test_allow_push_with_no_setting
    mock_adapter = mock('git_adapter')
    mock_adapter.expects(:get_config_setting).with('receivepack').returns('')
    test_git = CompatibleGitAdapter.new(mock_adapter)

    assert ! test_git.allow_push?, 'Expected allow_push? to return false'
  end

  def test_allow_pull_with_true_setting
    mock_adapter = mock('git_adapter')
    mock_adapter.expects(:get_config_setting).with('uploadpack').returns('true')
    test_git = CompatibleGitAdapter.new(mock_adapter)

    assert test_git.allow_pull?, 'Expected allow_pull? to return true'
  end

  def test_allow_pull_with_false_setting
    mock_adapter = mock('git_adapter')
    mock_adapter.
      expects(:get_config_setting).
      with('uploadpack').
      returns('false')
    test_git = CompatibleGitAdapter.new(mock_adapter)

    assert ! test_git.allow_pull?, 'Expected allow_pull? to return false'
  end

  def test_allow_pull_with_no_setting
    mock_adapter = mock('git_adapter')
    mock_adapter.expects(:get_config_setting).with('uploadpack').returns('')
    test_git = CompatibleGitAdapter.new(mock_adapter)

    assert test_git.allow_pull?, 'Expected allow_pull? to return true'
  end

end
