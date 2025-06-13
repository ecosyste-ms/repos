require 'test_helper'

class ApiV1OwnersControllerTest < ActionDispatch::IntegrationTest
  setup do
    @host = Host.create(name: 'GitHub', url: 'https://github.com', kind: 'github')
    @owner = @host.owners.create(login: 'ecosyste-ms')
    @hidden_owner = @host.owners.create(login: 'hidden-owner', hidden: true)
  end

  test 'list owners for a host' do
    get api_v1_host_owners_path(host_id: @host.name)
    assert_response :success
    assert_template 'owners/index', file: 'owners/index.json.jbuilder'
    
    actual_response = JSON.parse(@response.body)

    assert_equal actual_response.length, 2
  end

  test 'get a owner for a host' do
    get api_v1_host_owner_path(host_id: @host.name, id: @owner.login)
    assert_response :success
    assert_template 'owners/show', file: 'owners/show.json.jbuilder'
    
    actual_response = JSON.parse(@response.body)

    assert_equal actual_response["login"], @owner.login
  end

  test 'get a hidden owner returns 404' do
    get api_v1_host_owner_path(host_id: @host.name, id: @hidden_owner.login)
    assert_response :not_found
  end

  test 'list repositories for a owner' do
    get repositories_api_v1_host_owner_path(host_id: @host.name, id: @owner.login)
    assert_response :success
    assert_template 'repositories/index', file: 'repositories/index.json.jbuilder'
    
    actual_response = JSON.parse(@response.body)

    assert_equal actual_response.length, 0
  end

  test 'list repositories for a hidden owner returns 404' do
    get repositories_api_v1_host_owner_path(host_id: @host.name, id: @hidden_owner.login)
    assert_response :not_found
  end
end