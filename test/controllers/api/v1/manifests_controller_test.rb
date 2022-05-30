require 'test_helper'

class ApiV1ManifestsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @host = Host.create(name: 'GitHub', url: 'https://github.com', kind: 'github')
    @repository = @host.repositories.create(full_name: 'ecosyste-ms/repos')
    @manifest = @repository.manifests.create(filepath: 'package.json')
  end

  test 'list manifests for a repository' do
    get api_v1_host_repository_manifests_path(host_id: @host.name, repository_id: @repository.full_name)
    assert_response :success
    assert_template 'manifests/index', file: 'repositories/manifests.json.jbuilder'
    
    actual_response = JSON.parse(@response.body)

    assert_equal actual_response.length, 1
  end
end