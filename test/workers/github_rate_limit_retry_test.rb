require 'test_helper'

class GithubRateLimitRetryTest < ActiveSupport::TestCase
  should 'delay by retry_after plus jitter when the token pool is unavailable' do
    exception = GithubRateLimitUnavailable.new(45)

    delay = SyncRepositoryWorker.sidekiq_retry_in_block.call(0, exception)

    assert_includes 45...(45 + GithubRateLimitRetry::JITTER), delay
  end

  should 'delay a GitLab 429 by about a minute' do
    stub_request(:get, 'https://gitlab.com/api/v4/users/1').to_return(status: 429, body: '{"message":"Retry later"}')
    exception = assert_raises(Gitlab::Error::TooManyRequests) { Gitlab.client(endpoint: 'https://gitlab.com/api/v4', private_token: 'test-token').user(1) }

    delay = SyncOwnerWorker.sidekiq_retry_in_block.call(0, exception)

    assert_includes GithubRateLimitRetry::GITLAB_RETRY_AFTER...(GithubRateLimitRetry::GITLAB_RETRY_AFTER + GithubRateLimitRetry::JITTER), delay
  end

  should 'fall back to default backoff for other errors' do
    assert_nil SyncRepositoryWorker.sidekiq_retry_in_block.call(0, StandardError.new)
  end

  should 'be included in every worker' do
    workers = ObjectSpace.each_object(Class).select { |c| c < Sidekiq::Worker }

    assert workers.all? { |w| w < GithubRateLimitRetry }
  end
end
