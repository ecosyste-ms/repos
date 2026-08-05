namespace :releases do
  desc 'Backfill GitHub release immutability'
  task :backfill_immutability, [:block_size, :after_name] => :environment do |_task, args|
    block_size = (args[:block_size] || 1_000).to_i
    repository_names = Repository.github_actions_package_names
    abort 'Unable to load GitHub Actions package names' unless repository_names

    puts "Loaded #{repository_names.size} GitHub Actions package names"
    processed, repositories_synced, repositories_missing, last_name = Release.backfill_immutability(
      repository_names: repository_names,
      block_size: block_size,
      after_name: args[:after_name]
    ) do |current_processed, current_synced, current_missing, current_name|
      puts "Processed #{current_processed} names, synced #{current_synced} repositories, missing #{current_missing}, last name #{current_name}"
    end
    puts "Done: processed #{processed} names, synced #{repositories_synced} repositories, missing #{repositories_missing}; last name #{last_name}"
  end
end
