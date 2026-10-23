class PingOwnerWorker
  include Sidekiq::Worker
  include GithubRateLimitRetry
  sidekiq_options queue: :ping, lock: :until_executed, lock_expiration: 1.day.to_i

  def perform(host_name, full_name, force = false)
    host = Host.find_by_name(host_name)
    return unless host
    owner = host.owners.find_by('lower(login) = ?', full_name.downcase)
    if owner
      owner.sync_async(force)
      owner.reping_repositories_async(force)
    else
      owner = host.sync_owner(full_name, force: force)
      owner&.reping_repositories_async(force)
    end
  end
end
