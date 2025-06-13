require 'test_helper'

class ApiV1RepositoriesControllerTest < ActionDispatch::IntegrationTest
  setup do
    @host = Host.create(name: 'GitHub', url: 'https://github.com', kind: 'github')
    @owner = @host.owners.create(login: 'ecosyste-ms')
    @hidden_owner = @host.owners.create(login: 'hidden-owner', hidden: true)
    @repository = @host.repositories.create(full_name: 'ecosyste-ms/repos', owner: 'ecosyste-ms', created_at: Time.now, updated_at: Time.now)
    @hidden_repository = @host.repositories.create(full_name: 'hidden-owner/repo', owner: 'hidden-owner', created_at: Time.now, updated_at: Time.now)
  end

  test 'list repositories for a host' do
    get api_v1_host_repositories_path(host_id: @host.name)
    assert_response :success
    assert_template 'repositories/index', file: 'repositories/index.json.jbuilder'
    
    actual_response = JSON.parse(@response.body)

    assert_equal actual_response.length, 2
  end

  test 'get repository names for a host' do
    get repository_names_api_v1_host_path(id: @host.name)
    assert_response :success
    
    actual_response = JSON.parse(@response.body)

    assert_equal actual_response.length, 2
    assert_includes actual_response, 'ecosyste-ms/repos'
    assert_includes actual_response, 'hidden-owner/repo'
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
    get api_v1_repositories_lookup_path(url: 'https://github.com/ecosyste-ms/repos/')
    assert_response :success
    assert_template 'repositories/show', file: 'repositories/show.json.jbuilder'
    
    actual_response = JSON.parse(@response.body)

    assert_equal actual_response["full_name"], @repository.full_name
  end

  test 'lookup a repository with hidden owner returns 404' do
    get api_v1_repositories_lookup_path(url: 'https://github.com/hidden-owner/repo/')
    assert_response :not_found
  end

  test 'get a repository by purl' do
    get api_v1_repositories_lookup_path(purl: 'pkg:github/ecosyste-ms/repos')
    assert_response :success
    assert_template 'repositories/show', file: 'repositories/show.json.jbuilder'
    
    actual_response = JSON.parse(@response.body)

    assert_equal actual_response["full_name"], @repository.full_name
  end

  test 'get a repository by purl with hidden owner returns 404' do
    get api_v1_repositories_lookup_path(purl: 'pkg:github/hidden-owner/repo')
    assert_response :not_found
  end
end