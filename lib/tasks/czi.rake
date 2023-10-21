namespace :czi do
  task github: :environment do
    host = Host.find_by(name: 'GitHub')

    names = Set.new
    owners = Set.new

    CSV.foreach('data/github_df.csv', headers: true) do |row|
      name = row['package_url'].gsub("https://github.com/",'').downcase
      names << name
      owners << name.split('/')[0]
    end;nil

    existing_names = Set.new
    missing_names = Set.new

    names.to_a.sort.each do |name|
      puts name
      repo = host.find_repository(name)
      if repo
        existing_names << name 
        if repo.last_synced_at.nil? || repo.last_synced_at < 1.month.ago
          puts "  Syncing #{name} #{repo.last_synced_at}"
          host.sync_repository_async(name) 
        end
        next if repo.fork?
        if repo.dependency_job_id.present? || repo.dependencies_parsed_at.nil? || repo.files_changed?
          "  Parsing extra details #{name}"
          repo.sync_extra_details_async
        end
      else
        puts "  Missing #{name}"
        missing_names << name
        host.sync_repository_async(name)
      end
    end;nil

    puts "Found #{names.size} names"
    puts "Found #{owners.size} owners"
    puts "Found #{existing_names.size} existing names"

    file = File.open('data/github.ndjson', 'a')

    existing_names.each do |name|
      puts name
      repo = host.find_repository(name)
      
      obj = repo.as_json(include: [manifests: {include: :dependencies}]).to_json

      file.puts JSON.generate(obj)
    end
  end
end