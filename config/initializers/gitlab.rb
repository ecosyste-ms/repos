module GitlabRequestFixes
  # gitlab-faraday sleeps for Retry-After inside the request on a 429, which holds a Sidekiq
  # thread for minutes or hours; raise straight away and let GithubRateLimitRetry reschedule
  %w[get post put patch delete].each do |method|
    define_method(method) do |path, options = {}|
      super(path, { ratelimit_retries: 1 }.merge(options))
    end
  end

  # gitlab-faraday passes paths like "/users", which Faraday resolves against the host root
  # and drops the endpoint's /api/v4
  def make_request(method, path, params)
    super(method, path.start_with?('/') ? "#{endpoint}#{path}" : path, params)
  end
end

Gitlab::Request.prepend(GitlabRequestFixes)
