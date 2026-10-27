module GithubRateLimitRetry
  extend ActiveSupport::Concern

  JITTER = 30
  GITLAB_RETRY_AFTER = 60

  included do
    sidekiq_retry_in do |_count, exception|
      case exception
      when GithubRateLimitUnavailable then exception.retry_after + rand(JITTER)
      when Gitlab::Error::TooManyRequests then GITLAB_RETRY_AFTER + rand(JITTER)
      end
    end
  end
end
