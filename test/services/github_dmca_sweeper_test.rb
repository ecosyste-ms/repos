require "test_helper"

class GithubDmcaSweeperTest < ActiveSupport::TestCase
  setup do
    @host = create(:github_host)
    @redis = mock("redis")
    @client = mock("public octokit client")
    @repository_client = mock("authenticated octokit client")
    @notice_connection = mock("raw content connection")
    @output = StringIO.new
    @sweeper = GithubDmcaSweeper.new(
      host: @host,
      client: @client,
      repository_client: @repository_client,
      notice_connection: @notice_connection,
      redis: @redis,
      output: @output
    )
  end

  test "removes only indexed repositories blocked for legal reasons" do
    blocked = create(:repository, host: @host, full_name: "Blocked/Repo", owner: "Blocked")
    original = create(:repository, host: @host, full_name: "Original/Work", owner: "Original")
    create(:repository, host: @host, full_name: "Unrelated/Repo", owner: "Unrelated")

    expect_comparison(<<~NOTICE)
      Original work: https://github.com/Original/Work
      Infringing file: https://github.com/Blocked/Repo/blob/main/copied.rb
      Duplicate link: https://github.com/blocked/repo
      Notice help: https://github.com/github/dmca/blob/master/README.md
      Profile only: https://github.com/Someone
    NOTICE

    @repository_client.expects(:repository).with("Original/Work").returns(stub)
    @repository_client.expects(:repository).with("Blocked/Repo").raises(Octokit::UnavailableForLegalReasons)

    result = @sweeper.sweep

    assert_nil Repository.find_by(id: blocked.id)
    assert Repository.exists?(original.id)
    assert_equal 1, result[:notice_files]
    assert_equal 2, result[:candidates]
    assert_equal 2, result[:indexed]
    assert_equal 1, result[:removed]
    assert_includes @output.string, "removing Blocked/Repo"
  end

  test "uses an anonymous client for github dmca" do
    anonymous_client = mock("anonymous octokit client")
    authenticated_client = mock("authenticated octokit client")
    host_instance = mock("github host instance")
    notice_connection = mock("notice connection")

    @host.stubs(:host_instance).returns(host_instance)
    host_instance.expects(:fetch_random_token).returns("token")
    Octokit::Client.expects(:new).with().returns(anonymous_client)
    Octokit::Client.expects(:new).with({access_token: "token"}).returns(authenticated_client)
    Faraday.expects(:new)
      .with(url: GithubDmcaSweeper::RAW_CONTENT_URL)
      .returns(notice_connection)
    anonymous_client.expects(:repository)
      .with(GithubDmcaSweeper::DMCA_REPOSITORY)
      .returns(stub(default_branch: "master"))
    anonymous_client.expects(:ref)
      .with(GithubDmcaSweeper::DMCA_REPOSITORY, "heads/master")
      .returns(stub(object: stub(sha: "head-sha")))

    sweeper = GithubDmcaSweeper.new(host: @host, redis: @redis, output: @output)

    assert_equal "head-sha", sweeper.current_head_sha
  end

  test "ignores non-notice and removed files" do
    @redis.expects(:get).with(GithubDmcaSweeper::CURSOR_KEY).returns("base-sha")
    expect_head
    comparison = stub(files: [
      stub(filename: "README.md", status: "modified"),
      stub(filename: "2026/08/removed.md", status: "removed")
    ])
    @client.expects(:compare).with(GithubDmcaSweeper::DMCA_REPOSITORY, "base-sha", "head-sha").returns(comparison)
    @redis.expects(:set).with(GithubDmcaSweeper::CURSOR_KEY, "head-sha")

    result = @sweeper.sweep

    assert_equal 0, result[:notice_files]
    assert_equal 0, result[:candidates]
  end

  test "uses a one week baseline on the first run" do
    @redis.expects(:get).with(GithubDmcaSweeper::CURSOR_KEY).returns(nil)
    expect_head
    @client.expects(:commits)
      .with(GithubDmcaSweeper::DMCA_REPOSITORY, has_entries(per_page: 1))
      .returns([stub(sha: "week-old-sha")])
    @client.expects(:compare)
      .with(GithubDmcaSweeper::DMCA_REPOSITORY, "week-old-sha", "head-sha")
      .returns(stub(files: []))
    @redis.expects(:set).with(GithubDmcaSweeper::CURSOR_KEY, "head-sha")

    result = @sweeper.sweep

    assert_equal "head-sha", result[:head_sha]
  end

  test "does not advance the cursor when a repository check fails" do
    create(:repository, host: @host, full_name: "Broken/Check", owner: "Broken")
    expect_comparison("https://github.com/Broken/Check", advance_cursor: false)
    @repository_client.expects(:repository).with("Broken/Check").raises(Octokit::InternalServerError)

    assert_raises(Octokit::InternalServerError) { @sweeper.sweep }
  end

  test "retries a SAML protected repository without authentication" do
    repository = create(:repository, host: @host, full_name: "Protected/Repo", owner: "Protected")
    expect_comparison("https://github.com/Protected/Repo")
    @repository_client.expects(:repository).with("Protected/Repo").raises(Octokit::SAMLProtected)
    @client.expects(:repository).with("Protected/Repo").raises(Octokit::UnavailableForLegalReasons)

    result = @sweeper.sweep

    assert_nil Repository.find_by(id: repository.id)
    assert_equal 1, result[:removed]
  end

  test "refuses a comparison at the GitHub file limit" do
    @redis.expects(:get).with(GithubDmcaSweeper::CURSOR_KEY).returns("base-sha")
    expect_head
    files = Array.new(GithubDmcaSweeper::MAX_COMPARISON_FILES) do |index|
      stub(filename: "2026/08/notice-#{index}.md", status: "added")
    end
    @client.expects(:compare)
      .with(GithubDmcaSweeper::DMCA_REPOSITORY, "base-sha", "head-sha")
      .returns(stub(files: files))

    error = assert_raises(RuntimeError) { @sweeper.sweep }
    assert_includes error.message, "300-file limit"
  end

  def expect_comparison(content, advance_cursor: true)
    @redis.expects(:get).with(GithubDmcaSweeper::CURSOR_KEY).returns("base-sha")
    expect_head
    file = stub(filename: "2026/08/notice.md", status: "added")
    @client.expects(:compare)
      .with(GithubDmcaSweeper::DMCA_REPOSITORY, "base-sha", "head-sha")
      .returns(stub(files: [file]))
    path = "/#{GithubDmcaSweeper::DMCA_REPOSITORY}/head-sha/#{file.filename}"
    @notice_connection.expects(:get)
      .with(path)
      .returns(stub(success?: true, body: content))
    if advance_cursor
      @redis.expects(:set).with(GithubDmcaSweeper::CURSOR_KEY, "head-sha")
    end
  end

  def expect_head
    @client.expects(:repository)
      .with(GithubDmcaSweeper::DMCA_REPOSITORY)
      .returns(stub(default_branch: "master"))
    reference = stub(object: stub(sha: "head-sha"))
    @client.expects(:ref)
      .with(GithubDmcaSweeper::DMCA_REPOSITORY, "heads/master")
      .returns(reference)
  end
end
