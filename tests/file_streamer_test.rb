require_relative 'test_helper'

require 'minitest/autorun'
require 'minitest/unit'
require 'tempfile'

require 'grack/file_streamer'

class FileStreamerTest < MiniTest::Test
  include Grack

  def setup
    @content = 'abcd' * 10_000
    @file = Tempfile.new('foo')
    @file.write(@content)
    @file.rewind
    @file.close
    @streamer = FileStreamer.new(@file.path)
  end

  def teardown
    @file.unlink
  end

  def test_to_path
    assert_equal @file.path, @streamer.to_path
  end

  def test_mtime
    assert_equal File.mtime(@file.path), @streamer.mtime
  end

  def test_each
    assert_equal @content, @streamer.to_enum.to_a.join
  end

end
