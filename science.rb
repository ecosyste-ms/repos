require 'csv'

ids = Set.new

Repository.active.source.where("length(metadata::text) > 2").each_row(block_size:10_000) do |repo|
  json = JSON.parse(repo["metadata"])
  if json['files']
    if json['files']["codemeta"].present?
      puts json['files']["codemeta"].present?
      ids << repo["id"]
    elsif json['files']["citation"].present?
      puts json['files']["citation"]
      ids << repo["id"]
    elsif json['files']["zenodo"].present?
      puts json['files']["zenodo"]
      ids << repo["id"]
    end
  end
end

all_repos = []

ids.each do |id|
  repo = Repository.find_by_id(id)
  next unless repo
  
  codemeta_file = repo.metadata['files']['codemeta'] if repo.metadata['files']['codemeta'].present?
  citation_file = repo.metadata['files']['citation'] if repo.metadata['files']['citation'].present?
  zenodo_file = repo.metadata['files']['zenodo'] if repo.metadata['files']['zenodo'].present?
  
  all_repos << [repo.full_name, repo.html_url, codemeta_file, citation_file, zenodo_file]
end

csv_string = CSV.generate do |csv|
  csv << ['Full Name', 'HTML URL', 'Codemeta', 'Citation', 'Zenodo']
  all_repos.each do |repo|
    csv << repo
  end
end

puts csv_string