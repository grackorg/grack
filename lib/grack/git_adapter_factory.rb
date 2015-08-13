require 'grack/git_adapter'

module Grack
  ##
  # A factory class that produces GitAdapter instances using a given
  # configuration.
  class GitAdapterFactory
    ##
    # Creates a new instance of this class.
    #
    # @param [String] bin_path the path to use for the Git binary.
    def initialize(bin_path = 'git')
      @bin_path = bin_path
    end

    ##
    # @return [GitAdapter] a Git adapter.
    def create
      GitAdapter.new(@bin_path)
    end
  end
end
