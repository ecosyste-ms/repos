require 'test_helper'

class ApiV1OwnersControllerTest < ActionDispatch::IntegrationTest
  setup do
    @host = Host.create(name: 'GitHub', url: 'https://github.com', kind: 'github')
    @owner = @host.owners.create(login: 'ecosyste-ms')
  end

  test 'list owners for a host' do
    get api_v1_host_owners_path(host_id: @host.name)
    assert_response :success
    assert_template 'owners/index', file: 'owners/index.json.jbuilder'
    
    actual_response = JSON.parse(@response.body)

    assert_equal actual_response.length, 1
  end

  test 'get a owner for a host' do
    get api_v1_host_owner_path(host_id: @host.name, id: @owner.login)
    assert_response :success
    assert_template 'owners/show', file: 'owners/show.json.jbuilder'
    
    actual_response = JSON.parse(@response.body)

    assert_equal actual_response["login"], @owner.login
  end
end