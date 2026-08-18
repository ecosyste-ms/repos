require 'test_helper'

class GithubRateLimitRetryTest < ActiveSupport::TestCase
  should 'delay by retry_after plus jitter when the token pool is unavailable' do
    exception = GithubRateLimitUnavailable.new(45)

    delay = SyncRepositoryWorker.sidekiq_retry_in_block.call(0, exception)

    assert_includes 45...(45 + GithubRateLimitRetry::JITTER), delay
  end

  should 'fall back to default backoff for other errors' do
    assert_nil SyncRepositoryWorker.sidekiq_retry_in_block.call(0, StandardError.new)
  end

  should 'be included in every worker' do
    workers = ObjectSpace.each_object(Class).select { |c| c < Sidekiq::Worker }

    assert workers.all? { |w| w < GithubRateLimitRetry }
  end
end
