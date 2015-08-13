module Grack
  ##
  # A Rack body implementation that streams a given IO object in chunks for a
  # Rack response.
  class IOStreamer
    ##
    # The number of bytes to read at a time from IO streams.
    READ_SIZE = 32768

    ##
    # Creates a new instance of this object.
    #
    # @param [#read] io a readable, IO-like object.
    # @param [Time] mtime a timestamp to use for the last modified header in the
    #   response.
    def initialize(io, mtime)
      @io = io
      @mtime = mtime
    end

    ##
    # The last modified time to report for the Rack response.
    attr_reader :mtime

    ##
    # Iterates over the wrapped IO object in chunks, yielding each one.
    #
    # @yieldparam [String] chunk a chunk read from the wrapped IO object.
    def each
      with_io do |io|
        while chunk = io.read(READ_SIZE) do
          yield(chunk)
        end
      end
    end

    private

    ##
    # @yieldparam [#read] io the wrapped IO object.
    def with_io
      yield(@io)
    end
  end
end
