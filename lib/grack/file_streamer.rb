require 'pathname'

require 'grack/io_streamer'

module Grack
  class FileStreamer
    def initialize(path)
      @path = Pathname.new(path)
    end

    def to_path
      @path.to_s
    end

    def mtime
      @path.mtime
    end

    def each(&b)
      @path.open { |io| IOStreamer.new(io, mtime).each(&b) }
    end
  end
end
