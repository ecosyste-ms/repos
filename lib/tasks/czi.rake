namespace :czi do
  task github: :environment do
    csv = CSV.read('data/github_df.csv', headers: true)

    host = Host.find_by(name: 'GitHub')

    names = Set.new

    csv.each do |row|
      names << row['package_url'].gsub("https://github.com/",'').downcase
    end

    owners = Set.new

    names.each do |name|
      owners << name.split('/')[0]
    end

    existing_names = Set.new

    names.each do |name|
      puts name
      if host.find_repository(name)
        existing_names << name 
      else
        host.sync_repository_async(name)
      end
    end

    puts "Found #{names.size} names"
    puts "Found #{owners.size} owners"
    puts "Found #{existing_names.size} existing names"
  end
end