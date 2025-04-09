class PingWorker
  include Sidekiq::Worker
  sidekiq_options queue: :ping, lock: :until_executed, lock_expiration: 1.day.to_i

  def perform(host_name, full_name, force = false)
    host = Host.find_by_name(host_name)
    return unless host
    repository = host.find_repository(full_name.downcase)
    if repository
      if !force && repository.last_synced_at && repository.last_synced_at > 1.week.ago
        # if recently synced, schedule for syncing 1 day later
        delay = (repository.last_synced_at + 1.day) - Time.now
        UpdateRepositoryWorker.perform_in(delay, repository.id)
        return
      end

      repository.sync_async
      repository.sync_extra_details_async if !repository.fork? && repository.files_changed?
    else
      host.sync_repository_async(full_name)
    end
  end
end
