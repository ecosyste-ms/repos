module GithubRateLimitRetry
  extend ActiveSupport::Concern

  JITTER = 30

  included do
    sidekiq_retry_in do |_count, exception|
      exception.retry_after + rand(JITTER) if exception.is_a?(GithubRateLimitUnavailable)
    end
  end
end
