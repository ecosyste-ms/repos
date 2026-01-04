source "https://rubygems.org"
git_source(:github) { |repo| "https://github.com/#{repo}.git" }

ruby '4.0.0'

# Rails components
gem "railties", "~> 8.1.1"
gem "activesupport", "~> 8.1.1"
gem "activemodel", "~> 8.1.1"
gem "activerecord", "~> 8.1.1"
gem "actionpack", "~> 8.1.1"
gem "actionview", "~> 8.1.1"

gem "secure_headers"
gem "sprockets-rails"
gem "pg"
gem "puma"
gem "jbuilder"
gem "bootsnap", require: false
gem "sassc-rails"
gem "faraday"
gem "faraday-retry"
gem "faraday-gzip"
gem "faraday-follow_redirects"
gem "faraday-multipart"
gem 'faraday-net_http_persistent'
gem "nokogiri"
gem "oj"
gem "redis"
gem "sidekiq"
gem 'sidekiq-unique-jobs'
gem "pagy", "~> 9.4.0"
gem "pghero"
gem "pg_query"
gem 'bootstrap'
gem 'rack-cors'
gem 'rswag-api'
gem 'rswag-ui'
gem "semantic"
gem "semantic_range"
gem "gitlab"
gem "octokit"
gem "groupdate"
gem 'jquery-rails'
gem 'chartkick'
gem 'google-protobuf'
gem "sanitize-url"
gem "commonmarker"
gem 'appsignal'
gem 'sitemap_generator'
gem 'counter_culture'
gem 'after_commit_action'
gem 'postgresql_cursor'
gem 'packageurl-ruby', require: 'package_url'
gem 'csv'
gem 'ostruct'
gem "rack-timeout"
gem "lograge"

# Translation
gem 'http_accept_language'
gem 'i18n'
gem 'rails-i18n'
gem 'enum_help'

group :development do
  gem "web-console"
  gem "i18n-tasks"
end

group :test do
  gem "shoulda-matchers"
  gem "shoulda-context", "~> 3.0.0.rc1"
  gem "webmock"
  gem "mocha"
  gem "rails-controller-testing"
  gem "factory_bot_rails"
  gem "database_cleaner-active_record"
end

gem "bootstrap-icons", require: "bootstrap_icons"

group :development, :test do
  gem "dotenv-rails", "~> 3.2"
end
