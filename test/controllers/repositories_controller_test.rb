require 'test_helper'

class RepositoriesControllerTest < ActionDispatch::IntegrationTest
  setup do
    @host = create(:host, name: 'GitHub', url: 'https://github.com', kind: 'github')
    @owner = create(:owner, host: @host, login: 'ecosyste-ms')
    @hidden_owner = create(:owner, host: @host, login: 'hidden-owner', hidden: true)
    @repository = create(:repository, host: @host, full_name: 'ecosyste-ms/repos', owner: @owner.login)
    @hidden_repository = create(:repository, host: @host, full_name: 'hidden-owner/repo', owner: @hidden_owner.login)
  end

  test 'get a repository for a host' do
    get host_repository_path(host_id: @host.name, id: @repository.full_name)
    assert_response :success
    assert_template 'repositories/show', file: 'repositories/show.html.erb'
  end

  test 'get a repository with hidden owner returns 404' do
    get host_repository_path(host_id: @host.name, id: @hidden_repository.full_name)
    assert_response :not_found
  end

  test 'get dependencies for repository with hidden owner returns 404' do
    get dependencies_host_repository_path(host_id: @host.name, id: @hidden_repository.full_name)
    assert_response :not_found
  end

  test 'get readme for repository with hidden owner returns 404' do
    get readme_host_repository_path(host_id: @host.name, id: @hidden_repository.full_name)
    assert_response :not_found
  end

  test 'get releases for a repository' do
    get releases_host_repository_path(host_id: @host.name, id: @repository.full_name)
    assert_response :success
    assert_template 'repositories/releases', file: 'repositories/releases.html.erb'
  end

  test 'get releases for repository with hidden owner returns 404' do
    get releases_host_repository_path(host_id: @host.name, id: @hidden_repository.full_name)
    assert_response :not_found
  end

  test 'get releases with semver sorting' do
    release1 = create(:release, repository: @repository, tag_name: 'v1.0.0', published_at: 1.day.ago)
    release2 = create(:release, repository: @repository, tag_name: 'v2.0.0', published_at: 2.days.ago)
    release3 = create(:release, repository: @repository, tag_name: 'v1.5.0', published_at: 3.days.ago)

    get releases_host_repository_path(host_id: @host.name, id: @repository.full_name, sort: 'semver')
    assert_response :success
    assert_equal [release2, release3, release1], assigns(:releases)
  end

  test 'releases with Markdown body content are rendered properly' do
    markdown_body = "### New Features\n\n- Added **bold** text support\n- Fixed line breaks\n\nThanks to all contributors!"
    create(:release, repository: @repository, tag_name: 'v1.0.0', body: markdown_body, published_at: Time.now)

    get releases_host_repository_path(host_id: @host.name, id: @repository.full_name)
    assert_response :success
    assert_match '<strong>bold</strong>', response.body
    assert_match 'New Features</h3>', response.body
    assert_match '<ul>', response.body
  end

  test 'get releases with prefix filter' do
    v4_release = create(:release, repository: @repository, tag_name: 'v4.1.0', published_at: 1.day.ago)
    v3_release = create(:release, repository: @repository, tag_name: 'v3.2.0', published_at: 2.days.ago)
    ipfs_release = create(:release, repository: @repository, tag_name: 'ipfs-http-1.0.0', published_at: 3.days.ago)
    other_release = create(:release, repository: @repository, tag_name: 'other-1.0.0', published_at: 4.days.ago)

    get releases_host_repository_path(host_id: @host.name, id: @repository.full_name, prefix: 'v4')
    assert_response :success
    assert_includes assigns(:releases), v4_release
    assert_not_includes assigns(:releases), v3_release
    assert_not_includes assigns(:releases), ipfs_release
    assert_not_includes assigns(:releases), other_release
  end

  test 'get releases with ipfs prefix filter' do
    v4_release = create(:release, repository: @repository, tag_name: 'v4.1.0', published_at: 1.day.ago)
    ipfs_release1 = create(:release, repository: @repository, tag_name: 'ipfs-http-1.0.0', published_at: 2.days.ago)
    ipfs_release2 = create(:release, repository: @repository, tag_name: 'ipfs-http-2.0.0', published_at: 3.days.ago)
    other_release = create(:release, repository: @repository, tag_name: 'other-1.0.0', published_at: 4.days.ago)

    get releases_host_repository_path(host_id: @host.name, id: @repository.full_name, prefix: 'ipfs-http-')
    assert_response :success
    assert_not_includes assigns(:releases), v4_release
    assert_includes assigns(:releases), ipfs_release1
    assert_includes assigns(:releases), ipfs_release2
    assert_not_includes assigns(:releases), other_release
  end

  test 'get releases with prefix filter and semver sorting' do
    v4_release1 = create(:release, repository: @repository, tag_name: 'v4.1.0', published_at: 1.day.ago)
    v4_release2 = create(:release, repository: @repository, tag_name: 'v4.2.0', published_at: 2.days.ago)
    v3_release = create(:release, repository: @repository, tag_name: 'v3.2.0', published_at: 3.days.ago)

    get releases_host_repository_path(host_id: @host.name, id: @repository.full_name, prefix: 'v4', sort: 'semver')
    assert_response :success
    assert_includes assigns(:releases), v4_release1
    assert_includes assigns(:releases), v4_release2
    assert_not_includes assigns(:releases), v3_release
    assert_equal [v4_release2, v4_release1], assigns(:releases)
  end

  test 'prefix filter is case insensitive' do
    v4_release = create(:release, repository: @repository, tag_name: 'V4.1.0', published_at: 1.day.ago)
    other_release = create(:release, repository: @repository, tag_name: 'other-1.0.0', published_at: 2.days.ago)

    get releases_host_repository_path(host_id: @host.name, id: @repository.full_name, prefix: 'v4')
    assert_response :success
    assert_includes assigns(:releases), v4_release
    assert_not_includes assigns(:releases), other_release
  end

  test 'get scorecard for a repository' do
    scorecard = create(:scorecard, repository: @repository)
    get scorecard_host_repository_path(host_id: @host.name, id: @repository.full_name)
    assert_response :success
    assert_template 'repositories/scorecard', file: 'repositories/scorecard.html.erb'
    assert_equal scorecard, assigns(:scorecard)
  end

  test 'get scorecard for repository without scorecard' do
    get scorecard_host_repository_path(host_id: @host.name, id: @repository.full_name)
    assert_response :success
    assert_template 'repositories/scorecard', file: 'repositories/scorecard.html.erb'
    assert_nil assigns(:scorecard)
  end

  test 'get scorecard for repository with hidden owner returns 404' do
    get scorecard_host_repository_path(host_id: @host.name, id: @hidden_repository.full_name)
    assert_response :not_found
  end

  test 'scorecard tab appears in navigation when scorecard exists' do
    create(:scorecard, repository: @repository)
    get host_repository_path(host_id: @host.name, id: @repository.full_name)
    assert_response :success
    assert_match /href="[^"]*scorecard[^"]*">Scorecard<\/a>/, response.body
  end

  test 'scorecard tab does not appear in navigation when no scorecard exists' do
    get host_repository_path(host_id: @host.name, id: @repository.full_name)
    assert_response :success
    assert_no_match /href="[^"]*scorecard[^"]*">Scorecard<\/a>/, response.body
  end

  test 'get scorecard with no checks data does not crash' do
    scorecard = create(:scorecard, repository: @repository, data: { 'score' => 5.0, 'checks' => [] })
    get scorecard_host_repository_path(host_id: @host.name, id: @repository.full_name)
    assert_response :success
    assert_template 'repositories/scorecard', file: 'repositories/scorecard.html.erb'
    assert_equal scorecard, assigns(:scorecard)
  end

  test 'get a repository with blocked topic returns 404' do
    blocked_repo = create(:repository, host: @host, full_name: 'test/blocked-repo', owner: @owner.login, topics: ['malwarebytes-unlocked-version'])
    ENV['BLOCKED_TOPICS'] = 'malwarebytes-unlocked-version,premiere-crack-2023'
    get host_repository_path(host_id: @host.name, id: blocked_repo.full_name)
    assert_response :not_found
    ENV.delete('BLOCKED_TOPICS')
  end

  test 'get dependencies for repository with blocked topic returns 404' do
    blocked_repo = create(:repository, host: @host, full_name: 'test/blocked-repo', owner: @owner.login, topics: ['premiere-crack-2023'])
    ENV['BLOCKED_TOPICS'] = 'malwarebytes-unlocked-version,premiere-crack-2023'
    get dependencies_host_repository_path(host_id: @host.name, id: blocked_repo.full_name)
    assert_response :not_found
    ENV.delete('BLOCKED_TOPICS')
  end

  test 'get readme for repository with blocked topic returns 404' do
    blocked_repo = create(:repository, host: @host, full_name: 'test/blocked-repo', owner: @owner.login, topics: ['download-free-dxo-photolab'])
    ENV['BLOCKED_TOPICS'] = 'download-free-dxo-photolab'
    get readme_host_repository_path(host_id: @host.name, id: blocked_repo.full_name)
    assert_response :not_found
    ENV.delete('BLOCKED_TOPICS')
  end

  test 'get releases for repository with blocked topic returns 404' do
    blocked_repo = create(:repository, host: @host, full_name: 'test/blocked-repo', owner: @owner.login, topics: ['malwarebytes-unlocked-version'])
    ENV['BLOCKED_TOPICS'] = 'malwarebytes-unlocked-version'
    get releases_host_repository_path(host_id: @host.name, id: blocked_repo.full_name)
    assert_response :not_found
    ENV.delete('BLOCKED_TOPICS')
  end

  test 'get scorecard for repository with blocked topic returns 404' do
    blocked_repo = create(:repository, host: @host, full_name: 'test/blocked-repo', owner: @owner.login, topics: ['premiere-crack-2023'])
    ENV['BLOCKED_TOPICS'] = 'premiere-crack-2023'
    get scorecard_host_repository_path(host_id: @host.name, id: blocked_repo.full_name)
    assert_response :not_found
    ENV.delete('BLOCKED_TOPICS')
  end
end