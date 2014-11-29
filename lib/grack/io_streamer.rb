module Grack
  class IOStreamer
    def initialize(io)
      @io = io
    end

    def each
      while chunk = @io.read(32768) do
        yield(chunk)
      end
    end
  end
end
