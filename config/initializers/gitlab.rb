# gitlab-faraday sleeps for Retry-After inside the request on a 429, which holds a Sidekiq
# thread for minutes or hours; raise straight away and let GithubRateLimitRetry reschedule
module GitlabRateLimitWithoutSleep
  %w[get post put patch delete].each do |method|
    define_method(method) do |path, options = {}|
      super(path, { ratelimit_retries: 1 }.merge(options))
    end
  end
end

Gitlab::Request.prepend(GitlabRateLimitWithoutSleep)
