class PingWorker
  include Sidekiq::Worker
  sidekiq_options queue: :ping

  def perform(host_name, full_name)
    host = Host.find_by_name(host_name)
    return unless host
    repository = host.repositories.find_by('lower(full_name) = ?', full_name.downcase)
    if repository
      repository.sync_async
    else
      host.sync_repository_async(full_name)
    end
  end
end
