class GithubDmcaSweeper
  DMCA_REPOSITORY = "github/dmca"
  RAW_CONTENT_URL = "https://raw.githubusercontent.com"
  CURSOR_KEY = "takedown:github_dmca:last_sha"
  MAX_COMPARISON_FILES = 300
  NOTICE_PATH = %r{\A\d{4}/(?:\d{2}/)?.+\.(?:md|markdown)\z}i
  GITHUB_REPOSITORY_URL = %r{https?://github\.com/([a-z0-9][a-z0-9-]*)/([a-z0-9_.-]+)}i

  def initialize(host: nil, client: nil, repository_client: nil, notice_connection: nil,
                 redis: REDIS, output: $stdout)
    @host = host || Host.find_by_name!("GitHub")
    @client = client || Octokit::Client.new
    @repository_client = repository_client || github_client
    @notice_connection = notice_connection || Faraday.new(url: RAW_CONTENT_URL)
    @redis = redis
    @output = output
  end

  def sweep
    head_sha = current_head_sha
    base_sha = @redis.get(CURSOR_KEY)
    base_sha ||= baseline_sha

    if base_sha == head_sha
      @redis.set(CURSOR_KEY, head_sha)
      return result(head_sha: head_sha)
    end

    comparison = @client.compare(DMCA_REPOSITORY, base_sha, head_sha)
    files = comparison.files.to_a
    if files.length >= MAX_COMPARISON_FILES
      raise "GitHub DMCA comparison reached the #{MAX_COMPARISON_FILES}-file limit"
    end

    notice_files = files.select { |file| notice_file?(file) }
    repository_names = repository_names_from(notice_files, head_sha)
    indexed_count = 0
    removed_count = 0

    repository_names.each do |repository_name|
      repository = @host.find_repository(repository_name)
      next unless repository

      indexed_count += 1
      if legally_blocked?(repository_name)
        @output.puts "[repos] removing #{repository.full_name} listed in github/dmca"
        repository.destroy!
        removed_count += 1
      end
    end

    @redis.set(CURSOR_KEY, head_sha)
    result(
      head_sha: head_sha,
      notice_files: notice_files.length,
      candidates: repository_names.length,
      indexed: indexed_count,
      removed: removed_count
    )
  end

  def github_client
    token = @host.host_instance.fetch_random_token
    options = {}
    options[:access_token] = token if token.present?
    Octokit::Client.new(options)
  end

  def current_head_sha
    repository = @client.repository(DMCA_REPOSITORY)
    reference = @client.ref(DMCA_REPOSITORY, "heads/#{repository.default_branch}")
    reference.object.sha
  end

  def baseline_sha
    commit = @client.commits(
      DMCA_REPOSITORY,
      until: 1.week.ago.iso8601,
      per_page: 1
    ).first
    raise "Unable to find a GitHub DMCA baseline commit" unless commit

    commit.sha
  end

  def notice_file?(file)
    file.status != "removed" && file.filename.match?(NOTICE_PATH)
  end

  def repository_names_from(files, head_sha)
    names = files.flat_map do |file|
      repository_names_in(notice_contents(file.filename, head_sha))
    end

    names.each_with_object({}) do |name, unique_names|
      unique_names[name.downcase] ||= name
    end.values
  end

  def notice_contents(path, head_sha)
    response = @notice_connection.get("/#{DMCA_REPOSITORY}/#{head_sha}/#{path}")
    raise "Unable to download GitHub DMCA notice #{path}: HTTP #{response.status}" unless response.success?

    response.body
  end

  def legally_blocked?(repository_name)
    check_repository(@repository_client, repository_name)
  rescue Octokit::SAMLProtected
    check_repository(@client, repository_name)
  end

  def check_repository(client, repository_name)
    client.repository(repository_name)
    false
  rescue Octokit::UnavailableForLegalReasons
    true
  end

  def repository_names_in(content)
    content.scan(GITHUB_REPOSITORY_URL).filter_map do |owner, repository|
      repository = repository.sub(/[.,;:]+\z/, "").delete_suffix(".git")
      name = "#{owner}/#{repository}"
      name unless name.casecmp?(DMCA_REPOSITORY)
    end
  end

  def result(head_sha:, notice_files: 0, candidates: 0, indexed: 0, removed: 0)
    {
      head_sha: head_sha,
      notice_files: notice_files,
      candidates: candidates,
      indexed: indexed,
      removed: removed
    }
  end
end
