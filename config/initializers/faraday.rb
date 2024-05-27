# require 'faraday/typhoeus'
# Faraday.default_adapter = :typhoeus

Octokit.middleware = Faraday::RackBuilder.new do |builder|
  builder.use Octokit::Middleware::FollowRedirects
  builder.use Octokit::Response::RaiseError
  builder.request :instrumentation
  builder.request :retry
  builder.adapter Faraday.default_adapter, accept_encoding: "gzip"
end