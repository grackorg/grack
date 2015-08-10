require 'rake/testtask'

task :default => :test
 
Rake::TestTask.new do |t|
    t.pattern = 'tests/**/*_test.rb'
end

namespace :grack do
  desc 'Start Grack'
  task :start do
    system "rackup config.ru -p 8080"
  end
end
 
desc 'Start everything'
multitask :start => [ 'grack:start' ]
