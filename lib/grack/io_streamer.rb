module Grack
  class IOStreamer
    def initialize(io, mtime)
      @io = io
      @mtime = mtime
    end

    def mtime
      @mtime
    end

    def each
      while chunk = @io.read(32768) do
        yield(chunk)
      end
    end
  end
end
