namespace :dependencies do
  # Tag dependencies parsed before d6739c7 hold the tag id in repository_id.
  # dependencies has no repository_id index, so rows are reached through their
  # tag manifests in id order and updated by manifest_id.
  desc 'Point dependencies parsed from tag manifests at the repository of their tag'
  task :backfill_tag_repository_ids, [:batch_size, :after_id] => :environment do |_task, args|
    batch_size = (args[:batch_size] || 1_000).to_i
    abort 'batch_size must be greater than zero' unless batch_size.positive?

    update_sql = <<~SQL.squish
      UPDATE dependencies
      SET repository_id = tags.repository_id, updated_at = :now
      FROM manifests
      INNER JOIN tags ON tags.id = manifests.tag_id
      WHERE dependencies.manifest_id = manifests.id
        AND manifests.id IN (:manifest_ids)
        AND dependencies.repository_id IS DISTINCT FROM tags.repository_id
    SQL

    last_id = args[:after_id].to_i
    manifests_processed = 0
    batches = 0
    dependencies_updated = 0

    loop do
      manifest_ids = Manifest.where.not(tag_id: nil).where('manifests.id > ?', last_id).order(:id).limit(batch_size).pluck(:id)
      break if manifest_ids.empty?

      # SET LOCAL ends with the transaction, so the timeout is only lifted for this batch.
      dependencies_updated += Dependency.transaction do
        Dependency.connection.execute('SET LOCAL statement_timeout = 0')
        Dependency.connection.update(Dependency.sanitize_sql([update_sql, { now: Time.current, manifest_ids: manifest_ids }]))
      end

      manifests_processed += manifest_ids.size
      batches += 1
      last_id = manifest_ids.last
      if batches == 1 || (batches % 100).zero?
        puts "Processed #{batches} batches, updated #{dependencies_updated} dependencies, last manifest id #{last_id}"
      end
    end

    puts "Done: processed #{manifests_processed} manifests in #{batches} batches, updated #{dependencies_updated} dependencies, last manifest id #{last_id}"
  end
end
