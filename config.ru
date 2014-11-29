$LOAD_PATH.unshift File.expand_path(File.dirname(__FILE__) + '/lib')

use Rack::ShowExceptions

require 'grack/app'
require 'grack/git_adapter'

config = {
  :root => './',
  :adapter => Grack::GitAdapter,
  :adapter_config => {:bin_path => '/usr/bin/git'},
  :allow_upload_pack => true,
  :allow_receive_pack => true,
}

run Grack::App.new(config)
