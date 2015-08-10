require 'simplecov'
SimpleCov.start do
  add_filter 'tests/'
end

$: << File.expand_path('../../lib', __FILE__)

def git_path
  ENV.fetch('GIT_PATH', 'git') # Path to git on test system
end

def stock_repo
  File.expand_path('../example/_git', __FILE__)
end

def example_repo
  File.expand_path('../example/example_repo.git', __FILE__)
end

def init_example_repository
  FileUtils.rm_rf(example_repo)
  FileUtils.cp_r(stock_repo, example_repo)
end
