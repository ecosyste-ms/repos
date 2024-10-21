class PingOwnerWorker
  include Sidekiq::Worker
  sidekiq_options queue: :ping, lock: :until_executed

  def perform(host_name, full_name)
    host = Host.find_by_name(host_name)
    return unless host
    owner = host.owners.find_by('lower(login) = ?', full_name.downcase)
    if owner
      owner.sync_async
    else
      host.sync_owner_async(full_name)
    end
  end
end
