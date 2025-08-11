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
end