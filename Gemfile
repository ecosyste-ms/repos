source "https://rubygems.org"
git_source(:github) { |repo| "https://github.com/#{repo}.git" }

ruby "3.2.0"

gem "rails", "~> 7.0.4"
gem "sprockets-rails"
gem "pg", "~> 1.4"
gem "puma", "~> 6.0"
gem "jbuilder"
gem "tzinfo-data", platforms: %i[ mingw mswin x64_mingw jruby ]
gem "bootsnap", require: false
gem "sassc-rails"
gem "faraday"
gem "faraday-retry"
gem "faraday-gzip"
gem "faraday-follow_redirects"
gem "nokogiri", '1.14.0'
gem "oj"
gem "hiredis"
gem "redis", '<5', require: ["redis", "redis/connection/hiredis"]
gem "sidekiq", '<7'
gem "sidekiq-unique-jobs"
gem "pagy"
gem "pghero"
gem "pg_query"
gem 'bootstrap'
gem "rack-attack"
gem "rack-attack-rate-limit", require: "rack/attack/rate-limit"
gem 'rack-cors'
gem 'rswag-api'
gem 'rswag-ui'
gem "semantic"
gem "semantic_range"
gem "gitlab"
gem "octokit"
gem "bugsnag"
gem "groupdate"
gem 'jquery-rails'
gem 'chartkick'
gem 'google-protobuf'
gem "sanitize-url"
gem 'faraday-typhoeus'
gem 'appsignal'

group :development, :test do
  gem "debug", platforms: %i[ mri mingw x64_mingw ]
end

group :development do
  gem "web-console"
end

group :test do
  gem "shoulda"
  gem "webmock"
  gem "mocha"
  gem "rails-controller-testing"
end
