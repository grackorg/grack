require 'pathname'

require 'grack/file_streamer'

module Grack
  ##
  # @deprecated Upgrade to a Git adapter implementation that implements the new
  #   interface.
  #
  # A Git adapter adapter (yes an adapter for an adapter) that allows old-style
  # Git adapter classes to be used.
  class CompatibleGitAdapter
    ##
    # Creates a new instance of this adapter.
    #
    # @param [GitAdapter-like] adapter an old-style Git adapter instance to
    #   wrap.
    def initialize(adapter)
      @adapter = adapter
    end

    ##
    # The path to the repository on which to operate.
    attr_reader :repository_path

    ##
    # Sets the path to the repository on which to operate.
    def repository_path=(path)
      @repository_path = Pathname.new(path)
    end

    ##
    # @return [Boolean] +true+ if the repository exists; otherwise, +false+.
    def exist?
      repository_path.exist?
    end

    ##
    # Process the pack file exchange protocol.
    #
    # @param [String] pack_type the type of pack exchange to perform.
    # @param [#read] io_in a readable, IO-like object providing client input
    #   data.
    # @param [#write] io_out a writable, IO-like object sending output data to
    #   the client.
    # @param [Hash] opts options to pass to the Git adapter's #handle_pack
    #   method.
    # @option opts [Boolean] :advertise_refs (false)
    def handle_pack(pack_type, io_in, io_out, opts = {})
      msg = ''
      msg = io_in.read unless opts[:advertise_refs]

      @adapter.send(
        pack_type.sub(/^git-/, '').gsub('-', '_').to_sym,
        repository_path.to_s,
        opts.merge(:msg => msg)
      ) do |result|
        while chunk = result.read(8192) do
          io_out.write(chunk)
        end
      end
    end

    ##
    # Returns an object suitable for use as a Rack response body to provide the
    # content of a file at _path_.
    # 
    # @param [Pathname] path the path to a file within the repository.
    #
    # @return [FileStreamer] a Rack response body that can stream the file
    #   content at _path_.
    # @return [nil] if _path_ does not exist.
    def file(path)
      full_path = @repository_path + path
      return nil unless full_path.exist?
      FileStreamer.new(full_path)
    end

    ##
    # Triggers generation of data necessary to service Git Basic HTTP clients.
    #
    # @return [void]
    def update_server_info
      @adapter.update_server_info(repository_path.to_s)
    end

    ##
    # @return [Boolean] +true+ if pushes should be allowed; otherwise; +false+.
    def allow_push?
      @adapter.get_config_setting('receivepack') == 'true'
    end

    ##
    # @return [Boolean] +true+ if pulls should be allowed; otherwise; +false+.
    def allow_pull?
      @adapter.get_config_setting('uploadpack') != 'false'
    end
  end
end
