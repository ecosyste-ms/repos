require 'test_helper'

class ApiV1RepositoriesControllerTest < ActionDispatch::IntegrationTest
  setup do
    @host = create(:github_host)
    @owner = create(:github_owner, host: @host)
    @org = create(:github_org, host: @host)
    @hidden_owner = create(:hidden_owner, host: @host)
    
    @repository = create(:github_repository, host: @host)
    @org_repository = create(:github_org_repository, host: @host)
    @hidden_repository = create(:hidden_repository, host: @host)
    
    # Create repositories for other host types
    @gitlab_host = create(:gitlab_host)
    @gitlab_owner = create(:gitlab_owner, host: @gitlab_host)
    @gitlab_repository = create(:gitlab_repository, host: @gitlab_host)
    
    @gitea_host = create(:gitea_host)
    @gitea_owner = create(:gitea_owner, host: @gitea_host)
    @gitea_repository = create(:gitea_repository, host: @gitea_host)
    
    @bitbucket_host = create(:bitbucket_host)
    @bitbucket_owner = create(:bitbucket_owner, host: @bitbucket_host)
    @bitbucket_repository = create(:bitbucket_repository, host: @bitbucket_host)
    
    @forgejo_host = create(:forgejo_host)
    @forgejo_owner = create(:forgejo_owner, host: @forgejo_host)
    @forgejo_repository = create(:forgejo_repository, host: @forgejo_host)
    
    @sourcehut_host = create(:sourcehut_host)
    @sourcehut_owner = create(:sourcehut_owner, host: @sourcehut_host)
    @sourcehut_repository = create(:sourcehut_repository, host: @sourcehut_host)
  end

  test 'list repositories for a host' do
    get api_v1_host_repositories_path(host_id: @host.name)
    assert_response :success
    assert_template 'repositories/index', file: 'repositories/index.json.jbuilder'
    
    actual_response = JSON.parse(@response.body)

    assert_equal actual_response.length, 3
  end

  test 'get repository names for a host' do
    get repository_names_api_v1_host_path(id: @host.name)
    assert_response :success
    
    actual_response = JSON.parse(@response.body)

    assert_equal actual_response.length, 3
    assert_includes actual_response, 'testuser/awesome-project'
    assert_includes actual_response, 'testorg/enterprise-app'
    assert_includes actual_response, 'hiddenuser/secret-project'
  end

  test 'get a repository for a host' do
    get api_v1_host_repository_path(host_id: @host.name, id: @repository.full_name)
    assert_response :success
    assert_template 'repositories/show', file: 'repositories/show.json.jbuilder'
    
    actual_response = JSON.parse(@response.body)

    assert_equal actual_response["full_name"], @repository.full_name
  end

  test 'get a repository with hidden owner returns 404' do
    get api_v1_host_repository_path(host_id: @host.name, id: @hidden_repository.full_name)
    assert_response :not_found
  end

  test 'get sbom for repository with hidden owner returns 404' do
    get sbom_api_v1_host_repository_path(host_id: @host.name, id: @hidden_repository.full_name)
    assert_response :not_found
  end

  test 'lookup a repository for a host' do
    get api_v1_repositories_lookup_path(url: 'https://github.com/testuser/awesome-project/')
    assert_response :success
    assert_template 'repositories/show', file: 'repositories/show.json.jbuilder'
    
    actual_response = JSON.parse(@response.body)

    assert_equal actual_response["full_name"], @repository.full_name
  end

  test 'lookup a repository with hidden owner returns 404' do
    get api_v1_repositories_lookup_path(url: 'https://github.com/hiddenuser/secret-project/')
    assert_response :not_found
  end

  test 'get a repository by purl' do
    get api_v1_repositories_lookup_path(purl: 'pkg:github/testuser/awesome-project')
    assert_response :success
    assert_template 'repositories/show', file: 'repositories/show.json.jbuilder'
    
    actual_response = JSON.parse(@response.body)

    assert_equal actual_response["full_name"], @repository.full_name
  end

  test 'get a repository by purl with hidden owner returns 404' do
    get api_v1_repositories_lookup_path(purl: 'pkg:github/hiddenuser/secret-project')
    assert_response :not_found
  end

  test 'purl lookup requires purl parameter' do
    get api_v1_repositories_lookup_path
    assert_response :not_found
  end

  test 'purl lookup with unsupported host type returns 404' do
    get api_v1_repositories_lookup_path(purl: 'pkg:unsupported/test/repo')
    assert_response :not_found
  end

  test 'purl lookup gitlab repository succeeds' do
    get api_v1_repositories_lookup_path(purl: 'pkg:gitlab/gitlabuser/gitlab-project')
    assert_response :success
    assert_template 'repositories/show', file: 'repositories/show.json.jbuilder'
    
    actual_response = JSON.parse(@response.body)
    assert_equal @gitlab_repository.full_name, actual_response['full_name']
  end

  test 'purl lookup gitea repository succeeds' do
    get api_v1_repositories_lookup_path(purl: 'pkg:gitea/giteauser/gitea-project')
    assert_response :success
    assert_template 'repositories/show', file: 'repositories/show.json.jbuilder'
    
    actual_response = JSON.parse(@response.body)
    assert_equal @gitea_repository.full_name, actual_response['full_name']
  end

  test 'purl lookup bitbucket repository succeeds' do
    get api_v1_repositories_lookup_path(purl: 'pkg:bitbucket/bbuser/bitbucket-project')
    assert_response :success
    assert_template 'repositories/show', file: 'repositories/show.json.jbuilder'
    
    actual_response = JSON.parse(@response.body)
    assert_equal @bitbucket_repository.full_name, actual_response['full_name']
  end

  test 'purl lookup forgejo repository succeeds' do
    get api_v1_repositories_lookup_path(purl: 'pkg:forgejo/forgejouser/forgejo-project')
    assert_response :success
    assert_template 'repositories/show', file: 'repositories/show.json.jbuilder'
    
    actual_response = JSON.parse(@response.body)
    assert_equal @forgejo_repository.full_name, actual_response['full_name']
  end

  test 'purl lookup sourcehut repository succeeds' do
    get api_v1_repositories_lookup_path(purl: 'pkg:sourcehut/srhtuser/sourcehut-project')
    assert_response :success
    assert_template 'repositories/show', file: 'repositories/show.json.jbuilder'
    
    actual_response = JSON.parse(@response.body)
    assert_equal @sourcehut_repository.full_name, actual_response['full_name']
  end

  test 'purl lookup with malformed purl handles errors gracefully' do
    # Test various malformed PURL formats - most will cause PackageURL.parse exceptions
    malformed_purls = [
      'not-a-purl',
      'pkg:github/only-one-part'  # Missing namespace part
    ]
    
    malformed_purls.each do |bad_purl|
      get api_v1_repositories_lookup_path(purl: bad_purl)
      assert_response :not_found, "Should return 404 for malformed PURL: #{bad_purl}"
    end
    
    # Test valid PURL format but nonexistent host type
    get api_v1_repositories_lookup_path(purl: 'pkg:nonexistent/user/repo')
    assert_response :not_found
  end

  test 'purl lookup case insensitive matching' do
    # Create a test repository for case sensitivity testing
    test_repo = @host.repositories.create!(
      full_name: 'TestUser/CamelCase-Repo',
      owner: 'TestUser',
      created_at: Time.now,
      updated_at: Time.now
    )
    
    # Test that lowercase PURL finds uppercase repository
    get api_v1_repositories_lookup_path(purl: 'pkg:github/testuser/camelcase-repo')
    assert_response :success
    
    actual_response = JSON.parse(@response.body)
    assert_equal 'TestUser/CamelCase-Repo', actual_response['full_name']
  end
end