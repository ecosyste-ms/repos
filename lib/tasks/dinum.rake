module Dinum
  extend self

  # Script to manage dinum data for the instance https://data.code.gouv.fr
  # This instance reference the repositories of the public administration in France

  # The master data for host and repos is stored in a YAML file
  # The file will describe general purpose hosts and state hosts
  # The general purpose hosts will be imported with only state owned owners
  # The state hosts will be imported with all the owners
  # Some hosts are ignored because they are not currently available (missconfigured, not reachable, etc)
  ACCOUNTS_FILE = "https://git.sr.ht/~codegouvfr/codegouvfr-sources/blob/main/comptes-organismes-publics_new_specs.yml"


  # Pretty names for common hosts
  HOST_NAMING_MAP = {
    'github.com' => 'GitHub',
    'gitlab.com' => 'GitLab',
    'framagit.org' => 'Framagit',
    'gitlab.ow2.org' => 'OW2'
  }

  # Forges which support standard synchronisation
  # By exemple source hut miss fetch_owner method and is not supported
  SUPPORTED_FORGES_KIND = Set[
    'github',
    'gitlab',
  ]

  # Parse the master data YAML file and return the data
  def accounts_data
    @accounts_data ||= begin
      response = Faraday.get ACCOUNTS_FILE
      data = YAML.safe_load(response.body, permitted_classes: [Date])
      data.select! { |k, v| !v['ignored_since'] || v['ignored_since'] < Date.today }
      puts "Total: #{data.size} forges"
      data
    end
  end

  # Extract the general purpose hosts from the master data
  def general_purpose_hosts
    @general_purpose_hosts ||= Dinum.accounts_data.select { |k, v| v['general_purpose'] }
  end

  # Extract the state hosts from the master data
  def state_hosts
    @state_hosts ||= Dinum.accounts_data.select { |k, v| !v['general_purpose'] }
  end

  def state_hosts?(host)
    Dinum.state_hosts.keys.include?(URI(host.url).host)
  end

  # Import the general purpose hosts with only state owned owners
  # after: skip all the hosts before this one
  # dry: do not perform any action
  def import_general_purpose_owner_repos(after: nil, dry: false)
    missing_owners = []
    owner_without_repos = []
    service_unknown = []
    skip = true if after

    Dinum.general_purpose_hosts.each do |host_url, host_data|
      forge = host_data['forge']
      groups = host_data['groups']
      url = "https://#{host_url}"
      host = Host
        .create_with(name: HOST_NAMING_MAP.fetch(url, host_url), kind: forge)
        .find_or_create_by!(url: url)

      if ! SUPPORTED_FORGES_KIND.include?(forge)
        puts "Unsupported forge: #{forge} for host: #{host.name}, not syncinc"
        next
      end

      puts "Syncing #{host.name} with #{groups.size} groups"

      groups.each do |owner_name, metadatas|
        puts owner_name

        if skip
          skip = false if owner_name == after
          next
        end
        next if dry
        owner = host.sync_owner(owner_name)
        if owner
          host.sync_owner_repositories(owner)
          owner.update_repositories_count
          owner_without_repos.append owner if owner.repositories_count == 0
        else
          puts "Owner not found: #{owner_name}"
          missing_owners.append owner_name
        end
      end
    end

    p "missing_owners: #{missing_owners}"
    p "owner_without_repos: #{owner_without_repos}"
    p "service_unknown: #{service_unknown}"
  end

  # Import the state hosts without any repos yet
  def import_state_hosts
    Dinum.state_hosts.each do |host_domain, host_data|
      forge = host_data['forge']
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

  # Method to perform a full synchronization for all state hosts
  def hosts_initial_full_synchronization
    Host.all.each do |host|
      next if state_hosts?(host)
      begin
        host_initial_full_synchronization(host)
      rescue StandardError => e
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
      begin
        response = Faraday.get(h.url+"/api/v4/projects?per_page=1")
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
      rescue StandardError => e
        host_log_message(h, e)
      end
    end
    puts "#{Host.where(repositories_count: 0).count} hosts with sync problem"
  end
end

namespace :dinum do
  desc "Import general purpose owner repos"
  task :import_general_purpose_owner_repos => :environment do
    Dinum.import_general_purpose_owner_repos
  end

  desc "Import state hosts"
  task :import_state_hosts => :environment do
    Dinum.import_state_hosts
  end

  desc "Hosts initial full synchronization"
  task :hosts_initial_full_synchronization => :environment do
    Dinum.hosts_initial_full_synchronization
  end

  desc "Hosts list sync problem"
  task :hosts_list_sync_problem => :environment do
    Dinum.hosts_list_sync_problem
  end

  desc "Destroy no longer used hosts"
  task :destroy_old_hosts => :environment do
    urls = Dinum.accounts_data.map { |host_domain, data| "https://#{host_domain}" }
    hosts = Host.where.not(url: urls)
    puts "!! Destroying #{hosts.count}/#{Host.count} hosts (enter to continue) !!"
    STDIN.gets
    hosts.destroy_all
  end
end