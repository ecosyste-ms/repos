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

    names.each do |name|
      puts name
      if host.find_repository(name)
        existing_names << name 
      else
        missing_names << name
      end
    end;nil

    puts "Found #{names.size} names"
    puts "Found #{owners.size} owners"
    puts "Found #{existing_names.size} existing names"
  end
end