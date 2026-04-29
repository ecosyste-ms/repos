class PingOwnerRepositoriesWorker
  include Sidekiq::Worker
  sidekiq_options queue: :ping, lock: :until_executed, lock_expiration: 1.day.to_i

  def perform(host_name, owner_login)
    host = Host.find_by_name(host_name)
    return unless host

    owner = host.owners.find_by('lower(login) = ?', owner_login.downcase)
    owner ||= host.sync_owner(owner_login)
    owner.sync_repositories if owner.present? && !owner.hidden?
  end
end
