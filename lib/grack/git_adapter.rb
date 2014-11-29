module Grack
  class GitAdapter
    READ_SIZE = 32768

    attr_accessor :repository_path

    def initialize(opts = {})
      @repository_path = nil
      @git_path = opts.fetch(:bin_path, 'git')
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
      @repository_path + path
    end

    def update_server_info
      command('update-server-info', [], nil, nil, repository_path)
    end

    def config(key)
      backticks('config', ['--local', key], repository_path.to_s).chomp
    end


    private

    attr_reader :git_path

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
      capture_io.string.chomp
    end
  end
end
