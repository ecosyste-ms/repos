require 'test_helper'

class ApiV1PackageNamesControllerTest < ActionDispatch::IntegrationTest
  setup do
    @host = Host.create!(name: 'GitHub', url: 'https://github.com', kind: 'github')
    @repository = @host.repositories.create!(full_name: 'ecosysteme-ms/dependents')
    @manifest = @repository.manifests.create!(ecosystem: 'docker')
    @dependency = @manifest.dependencies.create!(package_name: 'ruby', repository: @repository)
  end

  test 'list unique docker names' do
    get docker_api_v1_package_names_path
    assert_response :success
    
    actual_response = JSON.parse(@response.body)

    assert_equal actual_response.length, 1
    assert_equal actual_response[0], 'library/ruby'
  end
end