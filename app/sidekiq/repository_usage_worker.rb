class RepositoryUsageWorker
  include Sidekiq::Worker
  include GithubRateLimitRetry
  sidekiq_options lock: :until_executed, lock_expiration: 1.day.to_i

  def perform(repository_id, preview = false)
    return RepositoryUsage.from_repository(Repository.find(repository_id)) unless preview

    RepositoryUsage.transaction(isolation: :repeatable_read) do
      connection = RepositoryUsage.connection
      connection.execute('SET TRANSACTION READ ONLY')
      connection.execute("SET LOCAL statement_timeout = '2s'")
      connection.execute("SET LOCAL lock_timeout = '250ms'")
      connection.execute('SET LOCAL jit = off')
      connection.execute('SET LOCAL max_parallel_workers_per_gather = 0')
      RepositoryUsage.packages_for_repository(Repository.find(repository_id))
    end
  end
end
