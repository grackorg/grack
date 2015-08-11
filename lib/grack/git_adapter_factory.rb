require 'grack/git_adapter'

module Grack
  class GitAdapterFactory
    def initialize(bin_path = 'git')
      @bin_path = bin_path
    end

    def create
      GitAdapter.new(@bin_path)
    end
  end
end
