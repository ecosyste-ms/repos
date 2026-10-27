module GitlabRequestFixes
  # gitlab-faraday sleeps for Retry-After inside the request on a 429, which holds a Sidekiq
  # thread for minutes or hours; raise straight away and let GithubRateLimitRetry reschedule
  %w[post put patch delete].each do |method|
    define_method(method) do |path, options = {}|
      super(path, { ratelimit_retries: 1 }.merge(options))
    end
  end

  # anonymous reads get a higher rate limit on gitlab.com; the token is only sent when a
  # server refuses them, such as user profiles or instances that require sign in
  def get(path, options = {})
    options = { ratelimit_retries: 1 }.merge(options)
    return super(path, options) if options[:unauthenticated] || private_token.blank?

    begin
      super(path, options.merge(unauthenticated: true))
    rescue Gitlab::Error::Unauthorized, Gitlab::Error::Forbidden
      super(path, options)
    end
  end

  # gitlab-faraday passes paths like "/users", which Faraday resolves against the host root
  # and drops the endpoint's /api/v4
  def make_request(method, path, params)
    super(method, path.start_with?('/') ? "#{endpoint}#{path}" : path, params)
  end
end

Gitlab::Request.prepend(GitlabRequestFixes)
