require 'pathname'
require 'rack/request'
require 'rack/response'
require 'time'
require 'zlib'

require 'grack/git_adapter'

##
# A namespace for all Grack functionality.
module Grack
  ##
  # A Rack application for serving Git repositories over HTTP.
  class App
    ##
    # A list of supported pack service types.
    VALID_SERVICE_TYPES = %w{git-upload-pack git-receive-pack}

    ##
    # Route mappings from URIs to valid verbs and handler functions.
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

    ##
    # Creates a new instance of this application with the configuration provided
    # by _opts_.
    #
    # @param [Hash] opts a hash of supported options.
    # @option opts [String] :root (Dir.pwd) a directory path containing 1 or
    #   more Git repositories.
    # @option opts [Boolean, nil] :allow_push (nil) determines whether or not to
    #   allow pushes into the repositories.  +nil+ means to defer to the
    #   requested repository.
    # @option opts [Boolean, nil] :allow_pull (nil) determines whether or not to
    #   allow fetches/pulls from the repositories.  +nil+ means to defer to the
    #   requested repository.
    # @option opts [#call] :git_adapter_factory (->{ GitAdapter.new }) a
    #   call-able object that creates Git adapter instances per request.
    def initialize(opts = {})
      opts = convert_old_opts(opts)

      @root                = Pathname.new(opts.fetch(:root, '.')).expand_path
      @allow_push          = opts.fetch(:allow_push, nil)
      @allow_pull          = opts.fetch(:allow_pull, nil)
      @git_adapter_factory =
        opts.fetch(:git_adapter_factory, ->{ GitAdapter.new })
    end

    ##
    # The Rack handler entry point for this application.  This duplicates the
    # object and uses the duplicate to perform the work in order to enable
    # thread safe request handling.
    #
    # @param [Hash] env a Rack request hash.
    #
    # @return a Rack response object.
    def call(env)
      dup._call(env)
    end

    protected

    ##
    # The real request handler.
    #
    # @param [Hash] env a Rack request hash.
    #
    # @return a Rack response object.
    def _call(env)
      @git = @git_adapter_factory.call
      @env = env
      @request = Rack::Request.new(env)
      route
    end

    private

    ##
    # The Rack request hash.
    attr_reader :env

    ##
    # The request object built from the request hash.
    attr_reader :request

    ##
    # The Git adapter instance for the requested repository.
    attr_reader :git

    ##
    # The path containing 1 or more Git repositories which may be requested.
    attr_reader :root

    ##
    # Determines whether or not pushes into the requested repository are
    # allowed.
    #
    # @return [Boolean] +true+ if pushes are allowed, +false+ otherwise.
    def allow_push?
      @allow_push || (@allow_push.nil? && git.allow_push?)
    end

    ##
    # Determines whether or not fetches/pulls from the requested repository are
    # allowed.
    #
    # @return [Boolean] +true+ if fetches are allowed, +false+ otherwise.
    def allow_pull?
      @allow_pull || (@allow_pull.nil? && git.allow_pull?)
    end

    ##
    # Routes requests to appropriate handlers.  Performs request path cleanup
    # and several sanity checks prior to attempting to handle the request.
    #
    # @return a Rack response object.
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

    ##
    # Processes pack file exchange requests for both push and pull.  Ensures
    # that the request is allowed and properly formatted.
    #
    # @param [String] pack_type the type of pack exchange to perform per the
    #   request.
    #
    # @return a Rack response object.
    def handle_pack(pack_type)
      unless request.content_type == "application/x-#{pack_type}-request" &&
             pack_type_allowed?(pack_type)
        return no_access
      end

      headers = {'Content-Type' => "application/x-#{pack_type}-result"}
      exchange_pack(pack_type, headers, request_io_in)
    end

    ##
    # Processes requests for the list of refs for the requested repository.
    #
    # This works for both Smart HTTP clients and basic ones.  For basic clients,
    # the Git adapter is used to update the +info/refs+ file which is then
    # served to the clients.  For Smart HTTP clients, the more efficient pack
    # file exchange mechanism is used.
    # 
    # @return a Rack response object.
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

    ##
    # Processes requests for info packs for the requested repository.
    #
    # @param [String] path the path to an info pack file within a Git
    #   repository.
    #
    # @return a Rack response object.
    def info_packs(path)
      send_file(git.file(path), 'text/plain; charset=utf-8', hdr_nocache)
    end

    ##
    # Processes a request for a loose object at _path_ for the selected
    # repository.  If the file is located, the content type is set to
    # +application/x-git-loose-object+ and permanent caching is enabled.
    #
    # @param [String] path the path to a loose object file within a Git
    #   repository, such as +objects/31/d73eb4914a8ddb6cb0e4adf250777161118f90+.
    #
    # @return a Rack response object.
    def loose_object(path)
      send_file(
        git.file(path), 'application/x-git-loose-object', hdr_cache_forever
      )
    end

    ##
    # Process a request for a pack file located at _path_ for the selected
    # repository.  If the file is located, the content type is set to
    # +application/x-git-packed-objects+ and permanent caching is enabled.
    #
    # @param [String] path the path to a pack file within a Git repository such
    #   as +pack/pack-62c9f443d8405cd6da92dcbb4f849cc01a339c06.pack+.
    #
    # @return a Rack response object.
    def pack_file(path)
      send_file(
        git.file(path), 'application/x-git-packed-objects', hdr_cache_forever
      )
    end

    ##
    # Process a request for a pack index file located at _path_ for the selected
    # repository.  If the file is located, the content type is set to
    # +application/x-git-packed-objects-toc+ and permanent caching is enabled.
    #
    # @param [String] path the path to a pack index file within a Git
    #   repository, such as
    #   +pack/pack-62c9f443d8405cd6da92dcbb4f849cc01a339c06.idx+.
    #
    # @return a Rack response object.
    def idx_file(path)
      send_file(
        git.file(path),
        'application/x-git-packed-objects-toc',
        hdr_cache_forever
      )
    end

    ##
    # Process a request for a generic file located at _path_ for the selected
    # repository.  If the file is located, the content type is set to
    # +text/plain+ and caching is disabled.
    #
    # @param [String] path the path to a file within a Git repository, such as
    #   +HEAD+.
    #
    # @return a Rack response object.
    def text_file(path)
      send_file(git.file(path), 'text/plain', hdr_nocache)
    end

    ##
    # Produces a Rack response that wraps the output from the Git adapter.
    #
    # A 404 response is produced if _streamer_ is +nil+.  Otherwise a 200
    # response is produced with _streamer_ as the response body.
    #
    # @param [FileStreamer,IOStreamer] streamer a provider of content for the
    #   response body.
    # @param [String] content_type the MIME type of the content.
    # @param [Hash] headers additional headers to include in the response.
    #
    # @return a Rack response object.
    def send_file(streamer, content_type, headers = {})
      return not_found if streamer.nil?

      headers['Content-Type'] = content_type
      headers['Last-Modified'] = streamer.mtime.httpdate

      [200, headers, streamer]
    end

    ##
    # Opens a tunnel for the pack file exchange protocol between the client and
    # the Git adapter.
    #
    # @param [String] pack_type the type of pack exchange to perform per the
    #   request.
    # @param [Hash] headers headers to provide in the Rack response.
    # @param [#read] io_in a readable, IO-like object providing client input
    #   data.
    # @param [Hash] opts options to pass to the Git adapter's #handle_pack
    #   method.
    # 
    # @return a Rack response object.
    def exchange_pack(pack_type, headers, io_in, opts = {})
      Rack::Response.new([], 200, headers).finish do |response|
        git.handle_pack(pack_type, io_in, response, opts)
      end
    end

    ##
    # Transparently ensures that the request body is not compressed.
    #
    # @return [#read] a +read+-able object that yields uncompressed data from
    #   the request body.
    def request_io_in
      return request.body unless env['HTTP_CONTENT_ENCODING'] =~ /gzip/
      Zlib::GzipReader.new(request.body)
    end

    ##
    # Determines whether or not _pack_type_ is valid.
    #
    # @param [String] pack_type the name of a pack type.
    #
    # @return [Boolean] +true+ if _pack_type_ is valid; otherwise, +false+.
    def pack_type_valid?(pack_type)
      VALID_SERVICE_TYPES.include?(pack_type)
    end

    ##
    # Determines whether or not _pack_type_ is allowed for the requested
    # repository.
    #
    # @param [String] pack_type the name of a pack type.
    #
    # @return [Boolean] +true+ if _pack_type_ is allowed for the requested
    #   repository; otherwise, +false+.
    def pack_type_allowed?(pack_type)
      return false unless pack_type_valid?(pack_type)
      return true if pack_type == 'git-receive-pack' && allow_push?
      return true if pack_type == 'git-upload-pack' && allow_pull?
      false
    end

    ##
    # Determines whether or not _path_ is an acceptable URI.
    #
    # @param [String] path the path part of the request URI.
    #
    # @return [Boolean] +true+ if the requested path is considered invalid;
    #   otherwise, +false+.
    def bad_uri?(path)
      invalid_segments = %w{. ..}
      path.split('/').any? { |segment| invalid_segments.include?(segment) }
    end

    # --------------------------------------
    # HTTP error response handling functions
    # --------------------------------------

    ##
    # A shorthand for specifying a text content type for the Rack response.
    PLAIN_TYPE = {'Content-Type' => 'text/plain'}

    ##
    # Returns a Rack response appropriate for requests that use invalid verbs
    # for the requested resources.
    #
    # For HTTP 1.1 requests, a 405 code is returned.  For other versions, the
    # value from #bad_request is returned.
    #
    # @return a Rack response appropriate for requests that use invalid verbs
    #   for the requested resources.
    def method_not_allowed
      if env['SERVER_PROTOCOL'] == 'HTTP/1.1'
        [405, PLAIN_TYPE, ['Method Not Allowed']]
      else
        bad_request
      end
    end

    ##
    # @return a Rack response for generally bad requests.
    def bad_request
      [400, PLAIN_TYPE, ['Bad Request']]
    end

    ##
    # @return a Rack response for unlocatable resources.
    def not_found
      [404, PLAIN_TYPE, ['Not Found']]
    end

    ##
    # @return a Rack response for forbidden resources.
    def no_access
      [403, PLAIN_TYPE, ['Forbidden']]
    end


    # ------------------------
    # header writing functions
    # ------------------------

    ##
    # NOTE: This should probably be converted to a constant.
    #
    # @return a hash of headers that should prevent caching of a Rack response.
    def hdr_nocache
      {
        'Expires'       => 'Fri, 01 Jan 1980 00:00:00 GMT',
        'Pragma'        => 'no-cache',
        'Cache-Control' => 'no-cache, max-age=0, must-revalidate'
      }
    end

    ##
    # @return a hash of headers that should trigger caches permanent caching.
    def hdr_cache_forever
      now = Time.now().to_i
      {
        'Date'          => now.to_s,
        'Expires'       => (now + 31536000).to_s,
        'Cache-Control' => 'public, max-age=31536000'
      }
    end

    ##
    # Converts old configuration settings to current ones.
    #
    # @param [Hash] opts an options hash to convert.
    # @option opts [String] :project_root a directory path containing 1 or more
    #   Git repositories.
    # @option opts [Boolean, nil] :receivepack determines whether or not to
    #   allow pushes into the repositories.  +nil+ means to defer to the
    #   requested repository.
    # @option opts [Boolean, nil] :uploadpack determines whether or not to
    #   allow fetches/pulls from the repositories.  +nil+ means to defer to the
    #   requested repository.
    # @option opts [#create] :adapter a class that provides an interface for
    #   interacting with Git repositories.
    #
    # @return an options hash with current options set based on old ones.
    def convert_old_opts(opts)
      opts = opts.dup

      if opts.key?(:project_root) && ! opts.key?(:root)
        opts[:root] = opts.fetch(:project_root)
      end
      if opts.key?(:upload_pack) && ! opts.key?(:allow_pull)
        opts[:allow_pull] = opts.fetch(:upload_pack)
      end
      if opts.key?(:receive_pack) && ! opts.key?(:allow_push)
        opts[:allow_push] = opts.fetch(:receive_pack)
      end
      if opts.key?(:adapter) && ! opts.key?(:git_adapter_factory)
        adapter = opts.fetch(:adapter)
        opts[:git_adapter_factory] =
          if GitAdapter == adapter
            ->{ GitAdapter.new(opts.fetch(:git_path, 'git')) }
          else
            require 'grack/compatible_git_adapter'
            ->{ CompatibleGitAdapter.new(adapter.new) }
          end
      end

      opts
    end
  end
end
