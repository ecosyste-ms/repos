namespace :releases do
  desc 'Backfill GitHub release immutability'
  task :backfill_immutability, [:batch_size, :after_id] => :environment do |_task, args|
    batch_size = (args[:batch_size] || 10_000).to_i
    after_id = (args[:after_id] || 0).to_i

    puts "Scanning releases after id #{after_id} in batches of #{batch_size}"
    scanned, repositories_synced, last_id = Release.backfill_immutability(
      batch_size: batch_size,
      after_id: after_id
    ) do |current_scanned, current_repositories_synced, current_id|
      puts "Scanned #{current_scanned} releases, synced #{current_repositories_synced} repositories, last id #{current_id}"
    end
    puts "Done: scanned #{scanned} releases and synced #{repositories_synced} repositories; last id #{last_id}"
  end
end
