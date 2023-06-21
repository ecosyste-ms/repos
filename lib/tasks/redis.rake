namespace :redis do
  desc 'export redis data'
  task :export => :environment do
    keys = ['last_timeline_id', 'bitbucket_next_crawl_url']

    Host.where(kind: 'gitea').each do |host|
      keys << "gitea_last_page:#{host.id}"
      keys << "gitea_token:#{host.id}"
    end

    Host.where(kind: 'gitlab').each do |host|
      keys << "gitlab_last_id:#{host.id}"
      keys << "gitlab_token:#{host.id}"
    end

    results = {}
    keys.each do |key|
      results[key] = REDIS.get(key)
    end

    File.open('redis.json', 'w') do |f|
      f.write(JSON.pretty_generate(results))
    end

    tokens = REDIS.smembers("github_tokens")
    File.open('github_tokens.json', 'w') do |f|
      f.write(JSON.pretty_generate(tokens))
    end

    puts JSON.pretty_generate(tokens)

    puts 

    puts JSON.pretty_generate(results)
  end

  desc 'import redis data'
  task :import => :environment do
    data = JSON.parse(File.read('redis.json'))
    data.each do |key, value|
      REDIS.set(key, value)
    end

    tokens = JSON.parse(File.read('github_tokens.json'))
    REDIS.sadd("github_tokens", tokens)
  end
end