namespace :owners do
  desc 'backfill metadata funding from .github repos'
  task backfill_funding: :environment do
    Host.where(kind: 'github').find_each do |host|
      count = 0
      host.owners.find_each do |owner|
        owner.update_funding
        count += 1
        puts "#{host.name}: #{count}" if (count % 10_000).zero?
      end
      puts "#{host.name}: #{count} owners processed"
    end
  end
end
