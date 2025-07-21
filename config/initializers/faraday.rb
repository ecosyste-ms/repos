Faraday.default_adapter = :net_http_persistent
Faraday.default_connection_options = {
  headers: {
    'User-Agent' => ENV.fetch('USER_AGENT', 'repos.ecosyste.ms')
  }
}

Octokit.middleware = Faraday::RackBuilder.new do |builder|
  builder.use Octokit::Middleware::FollowRedirects
  builder.use Octokit::Response::RaiseError
  builder.request :instrumentation
  builder.request :retry
  builder.request :retry, max: 5, interval: 0.05, backoff_factor: 2, exceptions: [Faraday::ConnectionFailed, Faraday::TimeoutError]
  builder.adapter Faraday.default_adapter, accept_encoding: "gzip"
end