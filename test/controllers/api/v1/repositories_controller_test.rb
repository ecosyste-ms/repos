require 'test_helper'

class ApiV1RepositoriesControllerTest < ActionDispatch::IntegrationTest
  setup do
    @host = Host.create(name: 'GitHub', url: 'https://github.com', kind: 'github')
    @repository = @host.repositories.create(full_name: 'ecosyste-ms/repos')
  end

  test 'list repositories for a host' do
    get api_v1_host_repositories_path(host_id: @host.name)
    assert_response :success
    assert_template 'repositories/index', file: 'repositories/index.json.jbuilder'
    
    actual_response = JSON.parse(@response.body)

    assert_equal actual_response.length, 1
  end

  test 'get a repository for a host' do
    get api_v1_host_repository_path(host_id: @host.name, id: @repository.full_name)
    assert_response :success
    assert_template 'repositories/show', file: 'repositories/show.json.jbuilder'
    
    actual_response = JSON.parse(@response.body)

    assert_equal actual_response["full_name"], @repository.full_name
  end

  test 'lookup a repository for a host' do
    get api_v1_repositories_lookup_path(url: 'https://github.com/ecosyste-ms/repos/')
    assert_response :success
    assert_template 'repositories/show', file: 'repositories/show.json.jbuilder'
    
    actual_response = JSON.parse(@response.body)

    assert_equal actual_response["full_name"], @repository.full_name
  end
end