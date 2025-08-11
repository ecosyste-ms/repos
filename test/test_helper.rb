ENV["RAILS_ENV"] ||= "test"
require_relative "../config/environment"
require "rails/test_help"

require 'webmock/minitest'
require 'mocha/minitest'
require 'factory_bot_rails'
require 'database_cleaner/active_record'

require 'sidekiq_unique_jobs/testing'
require 'sidekiq/testing'
Sidekiq::Testing.fake!

DatabaseCleaner.strategy = :truncation

class ActiveSupport::TestCase
  include FactoryBot::Syntax::Methods
  
  setup do
    DatabaseCleaner.clean
  end
  
  Shoulda::Matchers.configure do |config|
    config.integrate do |with|
      with.test_framework :minitest
      with.library :rails
    end
  end
end
