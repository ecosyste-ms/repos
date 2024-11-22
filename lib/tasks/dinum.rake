module Dinum
  extend self

  # Script to manage dinum data for the instance https://data.code.gouv.fr
  # This instance reference the repositories of the public administration in France

  # The master data for host and repos is stored in a YAML file
  # The file will describe general purpose hosts and pso hosts
  # The general purpose hosts will be imported with only pso owned owners
  # The pso hosts will be imported with all the owners
  # Some hosts are ignored because they are not currently available (missconfigured, not reachable, etc)
  ACCOUNTS_FILE = "https://code.gouv.fr/data/comptes-organismes-publics.yml"

  # Pretty names for common hosts
  HOST_NAMING_MAP = {
    "github.com" => "GitHub",
    "gitlab.com" => "GitLab",
    "framagit.org" => "Framagit",
    "gitlab.ow2.org" => "OW2"
  }

  # Forges which support standard synchronisation
  # By exemple source hut miss fetch_owner method and is not supported
  SUPPORTED_FORGES_KIND = Set[
    "github",
    "gitlab",
  ]

  # Parse the master data YAML file and return the data
  def accounts_data
    @accounts_data ||= begin
      response = Faraday.get ACCOUNTS_FILE
      data = YAML.safe_load(response.body, permitted_classes: [Date])
      data.select! { |k, v| !v["ignored_since"] || v["ignored_since"] < Date.today }
      puts "[accounts_data] Total: #{data.size} forges"
      data
    end
  end

  # Extract the general purpose hosts from the master data
  def general_purpose_hosts
    @general_purpose_hosts ||= Dinum.accounts_data.select { |k, v| v["owners"] }
  end

  # Extract the pso hosts from the master data
  def pso_hosts
    @pso_hosts ||= Dinum.accounts_data.select { |k, v| !v["owners"] }
  end

  def pso_hosts?(host)
    Dinum.pso_hosts.keys.include?(URI(host.url).host)
  end

  # Import the general purpose hosts with only pso owned owners
  # after: skip all the hosts before this one
  # dry: do not perform any action
  def import_general_purpose_owner_repos(after: nil, dry: false, sync_repositories: true)
    missing_owners = []
    owner_without_repos = []
    service_unknown = []
    skip = true if after

    Dinum.general_purpose_hosts.each do |host_url, host_data|
      forge = host_data["forge"]
      owners = host_data["owners"]
      url = "https://#{host_url}"
      host = Host
        .create_with(name: HOST_NAMING_MAP.fetch(url, host_url), kind: forge)
        .find_or_create_by!(url: url)

      if !SUPPORTED_FORGES_KIND.include?(forge)
        puts "Unsupported forge: #{forge} for host: #{host.name}, not syncinc"
        next
      end

      puts "Syncing #{host.name} with #{owners.size} owners"

      owners.each do |owner_name, metadatas|
        puts owner_name

        if skip
          skip = false if owner_name == after
          next
        end
        next if dry
        owner = host.sync_owner(owner_name)
        if owner
          if sync_repositories
            host.sync_owner_repositories(owner)
            owner.update_repositories_count
            owner_without_repos.append owner if owner.repositories_count == 0
          end
        else
          puts "Owner not found: #{owner_name} or kind == user"
          missing_owners.append [forge, owner_name]
        end
      end
    end

    p "missing_owners: #{missing_owners}"
    p "owner_without_repos: #{owner_without_repos}"
    p "service_unknown: #{service_unknown}"
  end

  # Import the pso hosts without any repos yet
  def import_pso_hosts
    Dinum.pso_hosts.each do |host_domain, host_data|
      forge = host_data["forge"]

      if !SUPPORTED_FORGES_KIND.include?(forge)
        puts "Unsupported forge: #{forge} for host: #{host_domain}, not syncinc"
        next
      end

      url = "https://#{host_domain}"
      host = Host
        .create_with(name: HOST_NAMING_MAP.fetch(url, host_domain), kind: forge)
        .find_or_create_by!(url: url)
    end
    puts "Total: #{Host.count} hosts"
  end

  # Method to perform a full synchronization for a host
  # crawl_repositories will fetch a batch of repositories from the host
  # The method will loop until the number of repositories fetched is the same as the previous batch
  def host_initial_full_synchronization(host)
    puts "Starting full synchronization for host: #{host.name} #{host.id}"
    host_reset(host) if host.repositories_count == 0
    loop do
      repo_count = host.repositories_count
      host.crawl_repositories
      sleep 1
      break if host.reload.repositories_count == repo_count
    end
  end

  # Method to perform a full synchronization for all pso hosts
  def hosts_initial_full_synchronization
    Host.all.each do |host|
      next if pso_hosts?(host)
      begin
        host_initial_full_synchronization(host)
      rescue => e
        puts "Error: #{e} for host: #{host.name}"
      end
    end
  end

  def host_log_message(host, message)
    puts "#{host.id} - #{host.url} - #{message}"
  end

  def host_reset(host)
    REDIS.del("gitlab_last_id:#{host.id}")
  end

  # Method to check all hosts to see if they are reachable with projects available
  # not working host should be marked in the master data file as ignored
  def hosts_list_sync_problem
    Host.where(repositories_count: 0, kind: :gitlab).each do |h|
      response = Faraday.get(h.url + "/api/v4/projects?per_page=1")
      if response.status != 200
        host_log_message(h, response.status)
        next
      end

      json = JSON.parse(response.body)
      if json.empty?
        host_log_message(h, "Empty")
      else
        # host_log_message(h, "OK")
      end
    rescue JSON::ParserError
      host_log_message(h, "JSON error")
    rescue Faraday::ConnectionFailed
      host_log_message(h, "ConnectionFailed")
    rescue Faraday::TimeoutError
      host_log_message(h, "TimeoutError")
    rescue Faraday::SSLError
      host_log_message(h, "SSLError")
    rescue OpenSSL::SSL::SSLError
      host_log_message(h, "SSLError")
    rescue Errno::ECONNREFUSED
      host_log_message(h, "ECONNREFUSED")
    rescue => e
      host_log_message(h, e)
    end
    puts "#{Host.where(repositories_count: 0).count} hosts with sync problem"
  end

  def hosts_run_async(pso:, &block)
    count = 0
    pool = Concurrent::FixedThreadPool.new(5)
    puts "Got a thread pool"
    Host.find_each.map do |host|
      puts "Host: #{host.name}"
      next if host.repositories_count == 0
      next if pso.present? && Dinum.pso_hosts?(host) != pso
      count += 1
      puts "- OK, will run async for host: #{host.name}"
      pool.post do
        begin
          puts "Running async for host: #{host.name}"
          ActiveRecord::Base.connection_pool.with_connection do
            block.call(host)
          end
        rescue => e
          puts "Error: #{e} for host: #{host.name}"
        ensure
          count -= 1
          pool.shutdown if count == 0
        end
      end
    end
    pool.wait_for_termination if count > 0
  ensure
    pool.shutdown
  end

  def repository_run_async(pso:, fork: nil, &block)
    hosts_run_async(pso: pso) do |host|
      repositories = host.repositories
      repositories = repositories.where(fork: fork) unless fork.nil?
      puts "Host: #{host.name} - Repositories: #{repositories.count}"
      repositories.find_each do |repo|
        next if fork == false && repo.fork
        next if fork == true && !repo.fork
        puts repo.full_name
        block.call(repo)
      rescue => e
        puts "Error: #{e} for repo: #{repo.full_name}"
      end
    end
  end

  def sync_extra_details(pso:, fork: nil)
    repository_run_async(pso:, fork:) do |r|
      r.sync_extra_details(force: true)
    end
  end

end

namespace :dinum do

  desc "set token in redis for a host"
  task set_token: :environment do
    host = Host.find_by!(name: ENV["HOST"])
    case host.kind
    when "github"
      REDIS.del("github_tokens")
      REDIS.sadd("github_tokens", ENV["TOKEN"])
    when "gitlab"
      REDIS.set("gitlab_token:#{host.id}", ENV["TOKEN"])
    else
      raise "Unsupported kind: #{host.kind}"
    end
  end

  desc "Create general purpose owner repos"
  task create_general_purpose_owner_repos: :environment do
    Dinum.import_general_purpose_owner_repos(sync_repositories: false)
  end

  desc "Import general purpose owner repos"
  task import_general_purpose_owner_repos: :environment do
    Dinum.import_general_purpose_owner_repos
  end

  desc "Import pso hosts"
  task import_pso_hosts: :environment do
    Dinum.import_pso_hosts
  end

  desc "Hosts initial full synchronization"
  task hosts_initial_full_synchronization: :environment do
    Dinum.hosts_initial_full_synchronization
  end

  desc "Hosts list sync problem"
  task hosts_list_sync_problem: :environment do
    Dinum.hosts_list_sync_problem
  end

  desc "Cleanup old data"
  task cleanup: [:destroy_old_hosts, :destroy_old_owners] do
  end


  desc "Destroy no longer used hosts"
  task destroy_old_hosts: :environment do
    urls = Dinum.accounts_data.map { |host_domain, data| "https://#{host_domain}" }
    hosts = Host.where.not(url: urls)
    if hosts.any?
      puts "!! Destroying #{hosts.count}/#{Host.count} hosts (enter to continue) !!"
      hosts.each { |h| puts h.url }
      STDIN.gets
      hosts.destroy_all
    else
      puts "No hosts to destroy"
    end
  end

  desc "Destroy no longer used owners"
  task destroy_old_owners: :environment do
    Dinum.general_purpose_hosts.each do |host_domain, host_data|
      host = Host.find_by(url: "https://#{host_domain}")
      next unless host
      logins = host_data["owners"].keys
      owners = host.owners.where(Owner.arel_table.lower(Owner.arel_table[:login]).not_in(logins.map(&:downcase)))
      if owners.any?
        puts "!! Destroying #{owners.count}/#{host.owners.count} owners for #{host.name} (enter to continue) !!"
        STDIN.gets
        owners.destroy_all
      end
      repositories = host.repositories.where(Repository.arel_table.lower(Repository.arel_table[:owner]).not_in(logins.map(&:downcase)))
      if repositories.any?
        puts "!! Destroying #{repositories.count}/#{host.repositories.count} repositories for #{host.name} (enter to continue) !!"
        STDIN.gets
        while repositories.any?
          puts repositories.count
          repositories.limit(500).destroy_all
        end
      end
    end
  end

  class GithubApiEstimator
    def initialize(api_client, sleep: false)
      @github = api_client
      @sleep = sleep
      reset_estimation
    end

    def update_calls(calls)
      @api_calls += calls
      if @api_calls >= 300 || Time.now > @last_reset + 3.minutes
        reset_estimation
      end

      while @sleep && @remaining-@api_calls < 500
        sleep_time = (@next_remaining_reset_at - Time.now).to_i + 1
        sleep_time = 60 if sleep_time < 60
        puts "Sleeping until reset time: #{sleep_time}s"
        sleep(sleep_time)
        reset_estimation
      end

      return @remaining - @api_calls
    end

    def reset_estimation
      puts "Resetting estimation"
      @api_calls = 0
      rate = @github.get('rate_limit')['rate']
      @remaining = rate['remaining']
      @next_remaining_reset_at = Time.at(rate['reset'])
      @last_reset = Time.now
    end
  end

  desc "Sync Github.com"
  task sync_github: :environment do
    github = Host.find_by(url: "https://github.com")
    estimator = GithubApiEstimator.new(github.host_instance.send(:api_client), sleep: true)
    started_at = Time.now
    repositories_synced = 0
    github
      .owners
      .sort_by{|owner| owner.repositories.maximum(:last_synced_at) || Time.at(0) }
      .each do |owner|
        puts "Syncing #{owner.name}"
        github.sync_owner_repositories(owner)
        owner.update_repositories_count

        remaining = estimator.update_calls(owner.repositories_count)
        break if remaining < 500

        puts "Finished syncing #{owner.name}, remaining api calls: #{remaining}, Syncing extra details"
        owner.repositories.each do |repo|
          repo.sync_extra_details(force: true)
        end

        remaining = estimator.update_calls(owner.repositories.count)
        break if remaining < 500
        puts "Finished syncing #{owner.name}, remaining api calls: #{remaining}"

        repositories_synced += owner.repositories_count
        puts "Total repositories synced: #{repositories_synced}"
        puts "Time elapsed: #{Time.now - started_at}"
        puts "Seconds per repository: #{(Time.now - started_at) / repositories_synced}"

        if Time.now - started_at > 5.hours
          puts "Time limit reached, stopping"
          break
        end
      end
  end
end

# To load in console :
# require 'rake'; Rails.application.load_tasks

# Some helpers command
# github = Host.find_by(name: "github.com")
