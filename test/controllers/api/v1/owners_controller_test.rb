require 'test_helper'

class ApiV1OwnersControllerTest < ActionDispatch::IntegrationTest
  setup do
    @host = Host.find_or_create_by(name: 'GitHub') do |h|
      h.url = 'https://github.com'
      h.kind = 'github'
    end
    @owner = @host.owners.create(login: 'ecosyste-ms', kind: :organization)
    @hidden_owner = @host.owners.create(login: 'hidden-owner', kind: :user, hidden: true)
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

  test 'get owner names for a host' do
    # Clean up any existing owners for this test
    @host.owners.destroy_all
    visible_owner = @host.owners.create!(login: 'visible-test', kind: :user)
    hidden_owner = @host.owners.create!(login: 'hidden-test', kind: :user, hidden: true)
    
    get names_api_v1_host_owners_path(host_id: @host.name)
    assert_response :success
    
    actual_response = JSON.parse(@response.body)

    assert_equal actual_response.length, 1
    assert_includes actual_response, 'visible-test'
    assert_not_includes actual_response, 'hidden-test'
  end

  test 'get owner names with kind filter' do
    # Clean up any existing owners for this test
    @host.owners.destroy_all
    user_owner = @host.owners.create!(login: 'user-test', kind: :user)
    org_owner = @host.owners.create!(login: 'org-test', kind: :organization)
    
    get names_api_v1_host_owners_path(host_id: @host.name, kind: 'user')
    assert_response :success
    
    actual_response = JSON.parse(@response.body)

    assert_equal actual_response.length, 1
    assert_includes actual_response, 'user-test'
    assert_not_includes actual_response, 'org-test'
  end
end