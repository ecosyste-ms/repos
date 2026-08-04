namespace :owners do
  desc 'backfill metadata funding from .github repos'
  task backfill_funding: :environment do
    Host.where(kind: 'github').find_each do |host|
      t0 = Time.now
      done = 0
      updated = 0
      puts "#{host.name}: declaring cursor over owners"
      host.owners.select(:id, :host_id, :login, :metadata).each_instance(with_hold: true) do |owner|
        repo = host.repositories.find_by('lower(full_name) = ?', "#{owner.login.downcase}/.github")
        funding = repo && repo.metadata['funding']
        if funding.present? && owner.metadata['funding'] != funding
          owner.update_column(:metadata, owner.metadata.merge('funding' => funding))
          updated += 1
        end
        done += 1
        if (done % 10_000).zero?
          rate = (done / (Time.now - t0)).round
          puts "#{host.name}: #{done} owners (#{updated} updated) #{rate}/s"
        end
      end
      puts "#{host.name}: #{done} owners (#{updated} updated) in #{(Time.now - t0).round}s"
    end
  end
end
