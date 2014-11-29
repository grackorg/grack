require 'grack/io_streamer'

module Grack
  class FileStreamer
    def initialize(path)
      @path = path
    end

    def to_path
      @path
    end

    def each(&b)
      @path.open { |io| IOStreamer.new(io).each(&b) }
    end
  end
end
