require 'bundler'
require "rspec/core/rake_task"

Bundler::GemHelper.install_tasks


task :default => :spec

# Run all the specs in the /spec folder
RSpec::Core::RakeTask.new


namespace :spec do
  desc "Run RSpec against all Ruby versions"
  task :rubies => "spec:rubies:default"

  namespace :rubies do
    RUBIES = %w( 1.8.7-p330 1.9.2-p0 jruby-1.5.6 ree-1.8.7-2010.02 )

    task :default => :ensure_rvm do
      sh "rvm #{RUBIES.join(",")} rake default"
    end

    task :ensure_rvm do
      File.exist?(File.expand_path("~/.rvm/scripts/rvm")) || abort("RVM is not available")
    end

    RUBIES.each do |ruby|
      desc "Run RSpec against Ruby #{ruby}"
      task ruby => :ensure_rvm do
        sh "rvm #{ruby} rake default"
      end
    end
  end

end
