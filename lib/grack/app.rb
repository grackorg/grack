require 'pathname'
require 'rack/request'
require 'rack/response'
require 'time'
require 'zlib'

require 'grack/file_streamer'
require 'grack/git_adapter_factory'
require 'grack/io_streamer'

module Grack
  class App
    VALID_SERVICE_TYPES = %w{git-upload-pack git-receive-pack}

    ROUTES = [
      [%r'/(.*?)/(git-(?:upload|receive)-pack)$',        'POST', :handle_pack],
      [%r'/(.*?)/info/refs$',                            'GET',  :info_refs],
      [%r'/(.*?)/(HEAD)$',                               'GET',  :text_file],
      [%r'/(.*?)/(objects/info/alternates)$',            'GET',  :text_file],
      [%r'/(.*?)/(objects/info/http-alternates)$',       'GET',  :text_file],
      [%r'/(.*?)/(objects/info/packs)$',                 'GET',  :info_packs],
      [%r'/(.*?)/(objects/info/[^/]+)$',                 'GET',  :text_file],
      [%r'/(.*?)/(objects/[0-9a-f]{2}/[0-9a-f]{38})$',   'GET',  :loose_object],
      [%r'/(.*?)/(objects/pack/pack-[0-9a-f]{40}\.pack)$', 'GET', :pack_file],
      [%r'/(.*?)/(objects/pack/pack-[0-9a-f]{40}\.idx)$', 'GET', :idx_file],
    ]

    def initialize(opts = {})
      @root                = Pathname.new(opts.fetch(:root, '.')).expand_path
      @allow_receive_pack  = opts.fetch(:allow_receive_pack, nil)
      @allow_upload_pack   = opts.fetch(:allow_upload_pack, nil)
      @git_adapter_factory = opts.fetch(:adapter_factory, GitAdapterFactory.new)
    end

    def call(env)
      dup._call(env)
    end

    def _call(env)
      @git = @git_adapter_factory.create
      @env = env
      @request = Rack::Request.new(env)
      route
    end

    private

    attr_reader :env
    attr_reader :request
    attr_reader :git
    attr_reader :root

    def allow_receive_pack?
      @allow_receive_pack ||
        (@allow_receive_pack.nil? && git.allow_receive_pack?)
    end

    def allow_upload_pack?
      @allow_upload_pack ||
        (@allow_upload_pack.nil? && git.allow_upload_pack?)
    end

    def route
      # Sanitize the URI:
      # * Unescape escaped characters
      # * Replace runs of / with a single /
      path_info = Rack::Utils.unescape(request.path_info).gsub(%r{/+}, '/')

      ROUTES.each do |path_matcher, verb, handler|
        path_info.match(path_matcher) do |match|
          repository_uri = match[1]

          return bad_request if bad_uri?(repository_uri)
          return method_not_allowed unless verb == request.request_method

          git.repository_path = root + repository_uri
          return not_found unless git.exist?

          return send(handler, *match[2..-1])
        end
      end
      not_found
    end

    def handle_pack(pack_type)
      unless request.content_type == "application/x-#{pack_type}-request" &&
             pack_type_allowed?(pack_type)
        return no_access
      end

      headers = {'Content-Type' => "application/x-#{pack_type}-result"}
      exchange_pack(pack_type, headers, request_io_in)
    end

    def info_refs
      pack_type = request.params['service']

      if pack_type_allowed?(pack_type)
        headers = hdr_nocache
        headers['Content-Type'] = "application/x-#{pack_type}-advertisement"
        exchange_pack(pack_type, headers, nil, {:advertise_refs => true})
      elsif pack_type.nil?
        git.update_server_info
        send_file(
          git.file('info/refs'), 'text/plain; charset=utf-8', hdr_nocache
        )
      else
        not_found
      end
    end

    def info_packs(path)
      send_file(git.file(path), 'text/plain; charset=utf-8', hdr_nocache)
    end

    def loose_object(path)
      send_file(
        git.file(path), 'application/x-git-loose-object', hdr_cache_forever
      )
    end

    def pack_file(path)
      send_file(
        git.file(path), 'application/x-git-packed-objects', hdr_cache_forever
      )
    end

    def idx_file(path)
      send_file(
        git.file(path),
        'application/x-git-packed-objects-toc',
        hdr_cache_forever
      )
    end

    def text_file(path)
      send_file(git.file(path), 'text/plain', hdr_nocache)
    end

    def send_file(streamer, content_type, headers = {})
      return not_found if streamer.nil?

      headers['Content-Type'] = content_type
      headers['Last-Modified'] = streamer.mtime.httpdate

      [200, headers, streamer]
    end

    def request_io_in
      return request.body unless env['HTTP_CONTENT_ENCODING'] =~ /gzip/
      Zlib::GzipReader.new(request.body)
    end

    def pack_type_valid?(pack_type)
      VALID_SERVICE_TYPES.include?(pack_type)
    end

    def pack_type_allowed?(pack_type)
      return false unless pack_type_valid?(pack_type)
      return true if pack_type == 'git-receive-pack' && allow_receive_pack?
      return true if pack_type == 'git-upload-pack' && allow_upload_pack?
      false
    end

    def exchange_pack(pack_type, headers, io_in, opts = {})
      Rack::Response.new([], 200, headers).finish do |response|
        git.handle_pack(pack_type, io_in, response, opts)
      end
    end

    def bad_uri?(path)
      invalid_segments = %w{. ..}
      path.split('/').any? { |segment| invalid_segments.include?(segment) }
    end

    # --------------------------------------
    # HTTP error response handling functions
    # --------------------------------------

    PLAIN_TYPE = {'Content-Type' => 'text/plain'}

    def method_not_allowed
      if env['SERVER_PROTOCOL'] == 'HTTP/1.1'
        [405, PLAIN_TYPE, ['Method Not Allowed']]
      else
        bad_request
      end
    end

    def bad_request
      [400, PLAIN_TYPE, ['Bad Request']]
    end

    def not_found
      [404, PLAIN_TYPE, ['Not Found']]
    end

    def no_access
      [403, PLAIN_TYPE, ['Forbidden']]
    end


    # ------------------------
    # header writing functions
    # ------------------------

    def hdr_nocache
      {
        'Expires'       => 'Fri, 01 Jan 1980 00:00:00 GMT',
        'Pragma'        => 'no-cache',
        'Cache-Control' => 'no-cache, max-age=0, must-revalidate'
      }
    end

    def hdr_cache_forever
      now = Time.now().to_i
      {
        'Date'          => now.to_s,
        'Expires'       => (now + 31536000).to_s,
        'Cache-Control' => 'public, max-age=31536000'
      }
    end
  end
end
