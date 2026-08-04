namespace :owners do
  desc 'backfill metadata funding from .github repos'
  task backfill_funding: :environment do
    Host.where(kind: 'github').find_each do |host|
      updated = 0
      scanned = 0
      host.repositories
          .where("lower(full_name) LIKE '%/.github'")
          .where("metadata->>'funding' IS NOT NULL")
          .each_instance do |repo|
        scanned += 1
        owner = host.owners.find_by('lower(login) = ?', repo.owner.downcase)
        next unless owner
        funding = repo.metadata['funding']
        next if owner.metadata['funding'] == funding
        owner.update_column(:metadata, owner.metadata.merge('funding' => funding))
        updated += 1
        puts "#{host.name}: #{updated} owners updated (#{scanned} .github repos scanned)" if (updated % 1000).zero?
      end
      puts "#{host.name}: #{updated} owners updated (#{scanned} .github repos with funding)"
    end
  end
end
