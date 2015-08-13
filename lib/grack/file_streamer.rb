require 'pathname'

require 'grack/io_streamer'

module Grack
  ##
  # A Rack body implementation that streams a given file in chunks for a Rack
  # response.
  class FileStreamer < IOStreamer
    ##
    # Creates a new instance of this object.
    #
    # @param [Pathname, String] path a path to a file.
    def initialize(path)
      @path = Pathname.new(path).expand_path
    end

    ##
    # In order to support X-Sendfile when available, this method returns the
    # path to the file the web server would use to provide the content.
    #
    # @return [String] the path to the file.
    def to_path
      @path.to_s
    end

    ##
    # The last modified time to report for the Rack response.
    def mtime
      @path.mtime
    end

    private

    ##
    # @yieldparam [#read] io the opened file.
    def with_io(&b)
      @path.open(&b)
    end
  end
end
