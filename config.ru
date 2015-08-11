$LOAD_PATH.unshift File.expand_path(File.dirname(__FILE__) + '/lib')

use Rack::ShowExceptions

require 'grack/app'
require 'grack/git_adapter_factory'

config = {
  :root => './',
  :allow_upload_pack => true,
  :allow_receive_pack => true,
  :adapter_factory => Grack::GitAdapterFactory.new
}

run Grack::App.new(config)
