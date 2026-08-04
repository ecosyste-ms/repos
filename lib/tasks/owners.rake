namespace :owners do
  desc 'backfill metadata funding from .github repos'
  task backfill_funding: :environment do
    Host.where(kind: 'github').find_each do |host|
      puts "#{host.name}: declaring cursor over owners"
      done, updated, secs = Owner.backfill_funding(host) do |d, u, rate|
        puts "#{host.name}: #{d} owners (#{u} updated) #{rate}/s"
      end
      puts "#{host.name}: #{done} owners (#{updated} updated) in #{secs}s"
    end
  end
end
