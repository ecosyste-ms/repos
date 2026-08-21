require_relative '../cron_lock'

namespace :hosts do
  desc 'check github tokens'
  task check_github_tokens: :environment do
    CronLock.acquire("hosts:check_github_tokens", ttl: 23.hours) do
      host = Host.find_by_name('GitHub')
      host.host_instance.check_tokens
    end
  end

  desc 'sync owners'
  task sync_owners: :environment do
    CronLock.acquire("hosts:sync_owners", ttl: 20.minutes) do
      Owner.sync_least_recently_synced
    end
  end

  desc 'Check status of all hosts'
  task check_status: :environment do
    CronLock.acquire("hosts:check_status", ttl: 23.hours) do
      Host.find_each do |host|
        host.check_status
      rescue => e
        # Silently continue on exceptions
      end
    end
  end

  desc 'Check status of stale hosts only'
  task check_stale_status: :environment do
    CronLock.acquire("hosts:check_stale_status", ttl: 1.hour) do
      Host.where('status_checked_at IS NULL OR status_checked_at < ?', 1.hour.ago).find_each do |host|
        host.check_status
      rescue => e
        # Silently continue on exceptions
      end
    end
  end

  desc 'Find public gitea/forgejo/gitlab instances with shodan.io. CREATE=true adds them'
  task discover: :environment do
    CronLock.acquire("hosts:discover", ttl: 1.hour) do
      create = ENV['CREATE'] == 'true'

      result = ShodanHostDiscovery.new(
        create: create,
        queries: ENV['QUERY'].presence || ShodanHostDiscovery::QUERIES,
        pages: ENV.fetch('PAGES', ShodanHostDiscovery::DEFAULT_PAGES),
        limit: ENV.fetch('LIMIT', ShodanHostDiscovery::DEFAULT_LIMIT)
      ).discover

      result[:candidates].each do |candidate|
        puts "[repos] #{candidate.kind} #{candidate.url}#{" #{candidate.version}" if candidate.version}"
      end

      if result[:candidates].any? && !create
        puts "[repos] add to db/seeds.rb or re-run with CREATE=true:"
        result[:candidates].each { |candidate| puts candidate.to_seed_line }
      end

      puts "[repos] shodan discovery found=#{result[:found]} probed=#{result[:probed]} candidates=#{result[:candidates].length} created=#{result[:created].length}"
    end
  rescue ShodanHostDiscovery::MissingApiKey, ShodanHostDiscovery::ApiError => e
    abort "[repos] #{e.message}"
  end

  desc 'Print the GitLab token stored in redis for HOST'
  task get_gitlab_token: :environment do
    host = Host.find_by_name!(ENV['HOST'].presence || 'GitLab')
    puts REDIS.get("gitlab_token:#{host.id}")
  end

  desc 'Store TOKEN in redis as the GitLab token for HOST'
  task set_gitlab_token: :environment do
    host = Host.find_by_name!(ENV['HOST'].presence || 'GitLab')
    REDIS.set("gitlab_token:#{host.id}", ENV.fetch('TOKEN'))
  end

  desc 'Rotate a GitLab personal access token and print the new one'
  task rotate_gitlab_token: :environment do
    token = ENV.fetch('TOKEN')
    url = ENV.fetch('URL', 'https://gitlab.com').chomp('/')
    expires_at = (Date.today + Integer(ENV.fetch('DAYS', '90'))).iso8601

    resp = Faraday.post("#{url}/api/v4/personal_access_tokens/self/rotate") do |req|
      req.headers['PRIVATE-TOKEN'] = token
      req.headers['Content-Type'] = 'application/json'
      req.body = { expires_at: expires_at }.to_json
    end

    abort "Rotation failed: #{resp.status} #{resp.body}" unless resp.success?

    json = JSON.parse(resp.body)
    puts "New token:  #{json['token']}"
    puts "Expires at: #{json['expires_at']}"
    puts "Scopes:     #{Array(json['scopes']).join(', ')}"
  end

  desc 'Rotate the redis-stored GitLab token for HOST, or every gitlab host with a token if HOST is unset'
  task refresh_gitlab_token: :environment do
    expires_at = (Date.today + Integer(ENV.fetch('DAYS', '90'))).iso8601

    hosts = if ENV['HOST'].present?
      [Host.find_by_name!(ENV['HOST'])]
    else
      Host.where(kind: 'gitlab').order(:name)
    end

    hosts.each do |host|
      key = "gitlab_token:#{host.id}"
      current = REDIS.get(key)
      if current.blank?
        puts "#{host.name}: no token, skipping" unless ENV['HOST'].present?
        abort "No token in redis at #{key}" if ENV['HOST'].present?
        next
      end

      resp = Faraday.post("#{host.url.chomp('/')}/api/v4/personal_access_tokens/self/rotate") do |req|
        req.headers['PRIVATE-TOKEN'] = current
        req.headers['Content-Type'] = 'application/json'
        req.body = { expires_at: expires_at }.to_json
      end

      unless resp.success?
        warn "#{host.name}: rotation failed: #{resp.status} #{resp.body}"
        next
      end

      json = JSON.parse(resp.body)
      puts "#{host.name}: new token #{json['token']} (expires #{json['expires_at']})"
      REDIS.set(key, json['token'])
    rescue => e
      warn "#{host.name}: #{e.class}: #{e.message}"
    end
  end
end