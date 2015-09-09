require 'pathname'

require 'grack/file_streamer'

module Grack
  ##
  # A wrapper for interacting with Git repositories using the git command line
  # tool.
  class GitAdapter
    ##
    # The number of bytes to read at a time from IO streams.
    READ_SIZE = 32768

    ##
    # Creates a new instance of this adapter.
    #
    # @param [String] bin_path the path to use for the Git binary.
    def initialize(bin_path = 'git')
      @repository_path = nil
      @git_path = bin_path
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
      args = %w{--stateless-rpc}
      if opts.fetch(:advertise_refs, false)
        str = "# service=#{pack_type}\n"
        io_out.write('%04x' % (str.size + 4))
        io_out.write(str)
        io_out.write('0000')
        args << '--advertise-refs'
      end
      args << repository_path.to_s
      command(pack_type.sub(/^git-/, ''), args, io_in, io_out)
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
      command('update-server-info', [], nil, nil, repository_path)
    end

    ##
    # @return [Boolean] +true+ if pushes should be allowed; otherwise; +false+.
    def allow_push?
      config('http.receivepack') == 'true'
    end

    ##
    # @return [Boolean] +true+ if pulls should be allowed; otherwise; +false+.
    def allow_pull?
      config('http.uploadpack') != 'false'
    end


    private

    ##
    # The path to use for running the git utility.
    attr_reader :git_path

    ##
    # @param [String] key a key to look up in the Git repository configuration.
    #
    # @return [String] the value for the given key.
    def config(key)
      capture_io = StringIO.new
      command('config', ['--local', key], nil, capture_io, repository_path.to_s)
      capture_io.string.chomp
    end

    ##
    # Runs the Git utilty with the given subcommand.
    #
    # @param [String] cmd
    # @param [Array<String>] args
    # @param [#read, nil] io_in
    # @param [#write, nil] io_out
    # @param [String] dir
    def command(cmd, args, io_in, io_out, dir = nil)
      cmd = [git_path, cmd] + args
      opts = {:err => :close}
      opts[:chdir] = dir unless dir.nil?
      cmd << opts
      IO.popen(cmd, 'r+b') do |pipe|
        while ! io_in.nil? && chunk = io_in.read(READ_SIZE) do
          pipe.write(chunk)
        end
        pipe.close_write
        while chunk = pipe.read(READ_SIZE) do
          io_out.write(chunk) unless io_out.nil?
        end
      end
    end
  end
end
