require_relative 'test_helper'

require 'minitest/autorun'
require 'minitest/unit'
require 'tempfile'

require 'grack/io_streamer'

class IOStreamerTest < MiniTest::Test
  include Grack

  def setup
    @content = 'abcd' * 10_000
    @file = Tempfile.new('foo')
    @file.write(@content)
    @file.rewind
    @streamer = IOStreamer.new(@file, @file.mtime)
  end

  def teardown
    @file.close
    @file.unlink
  end

  def test_to_path
    assert ! @streamer.respond_to?(:to_path), 'responds to #to_path'
  end
  def test_mtime
    assert_equal File.mtime(@file.path), @streamer.mtime
  end

  def test_each
    assert_equal @content, @streamer.to_enum.to_a.join
  end

end
