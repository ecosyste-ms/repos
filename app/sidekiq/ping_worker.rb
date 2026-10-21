class PingWorker
  include Sidekiq::Worker
  include GithubRateLimitRetry
  sidekiq_options queue: :ping, lock: :until_executed, lock_expiration: 1.day.to_i

  def perform(host_name, full_name, force = false)
    host = Host.find_by_name(host_name)
    return unless host
    repository = host.find_repository(full_name.downcase)
    if repository
      repository.sync_async(force)
      if (force || repository.sync_due?) && !repository.fork? && repository.files_changed?
        repository.sync_extra_details_async
      end
    else
      host.sync_repository_async(full_name)
    end
  end
end
