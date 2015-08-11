require 'pathname'

require 'grack/file_streamer'

module Grack
  class GitAdapter
    READ_SIZE = 32768

    attr_reader :repository_path

    def initialize(bin_path = 'git')
      @repository_path = nil
      @git_path = bin_path
    end

    def repository_path=(path)
      @repository_path = Pathname.new(path)
    end

    def exist?
      repository_path.exist?
    end

    def handle_pack(kind, io_in, io_out, opts = {})
      args = %w{--stateless-rpc}
      if opts.fetch(:advertise_refs, false)
        str = "# service=#{kind}\n"
        io_out.write('%04x' % (str.size + 4))
        io_out.write(str)
        io_out.write('0000')
        args << '--advertise-refs'
      end
      args << repository_path.to_s
      command(kind.sub(/^git-/, ''), args, io_in, io_out)
    end

    def file(path)
      full_path = @repository_path + path
      return nil unless full_path.exist?
      FileStreamer.new(full_path)
    end

    def update_server_info
      command('update-server-info', [], nil, nil, repository_path)
    end

    def allow_receive_pack?
      config('http.receivepack') == 'true'
    end

    def allow_upload_pack?
      config('http.uploadpack') == 'true'
    end


    private

    attr_reader :git_path

    def config(key)
      backticks('config', ['--local', key], repository_path.to_s).chomp
    end

    def command(cmd, args, io_in, io_out, dir = nil)
      cmd = [git_path, cmd] + args
      opts = {:err => :close}
      opts[:chdir] = dir unless dir.nil?
      cmd << opts
      IO.popen(cmd, 'r+') do |pipe|
        while ! io_in.nil? && chunk = io_in.read(READ_SIZE) do
          pipe.write(chunk)
        end
        pipe.close_write
        while chunk = pipe.read(READ_SIZE) do
          io_out.write(chunk) unless io_out.nil?
        end
      end
    end

    def backticks(cmd, args, dir = nil)
      capture_io = StringIO.new
      command(cmd, args, nil, capture_io, dir)
      capture_io.string
    end
  end
end
