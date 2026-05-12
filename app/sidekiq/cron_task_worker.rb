require "rake"

class CronTaskWorker
  include Sidekiq::Worker

  ALLOWED_TASKS = [
    "repositories:sync_least_recent",
    "repositories:sync_extra_details",
    "repositories:sync_recently_active",
    "hosts:sync_owners",
    "repositories:parse_missing_dependencies",
    "repositories:download_tags",
    "repositories:crawl",
    "packages:sync_registries",
    "packages:sync_packages",
    "hosts:check_github_tokens",
    "hosts:check_status",
    "sitemap:refresh_with_lock",
    "repositories:fetch_dependencies_for_github_actions_tags",
    "repositories:clean_up_sidekiq_unique_jobs",
    "gharchive:import_recent"
  ].freeze

  sidekiq_options lock: :until_executed, lock_expiration: 1.day.to_i

  def perform(task_name)
    raise ArgumentError, "Unsupported cron task: #{task_name}" unless ALLOWED_TASKS.include?(task_name)

    Rails.application.load_tasks unless Rake::Task.task_defined?(task_name)

    task = Rake::Task[task_name]
    task.reenable
    task.invoke
  end
end
