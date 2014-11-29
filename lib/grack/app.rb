require 'grack/request_handler'

module Grack
  class App
    def initialize(config)
      @config = config
    end

    attr_reader :config

    def call(env)
      RequestHandler.new(config).call(env)
    end
  end
end
