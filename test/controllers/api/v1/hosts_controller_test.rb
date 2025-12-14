require 'test_helper'

class ApiV1HostsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @host = Host.find_or_create_by(name: 'GitHub') do |h|
      h.url = 'https://github.com'
      h.kind = 'github'
    end
    @visible_owner = @host.owners.create!(login: 'visible-owner', kind: :user)
    @hidden_owner = @host.owners.create!(login: 'hidden-owner', kind: :organization, hidden: true)
  end

  test 'lists hosts' do
    get api_v1_hosts_path
    assert_response :success
    assert_template 'hosts/index', file: 'hosts/index.json.jbuilder'
    
    actual_response = JSON.parse(@response.body)

    assert_equal actual_response.length, 1
  end

  test 'get a host' do
    get api_v1_host_path(id: @host.name)
    assert_response :success
    assert_template 'hosts/show', file: 'hosts/show.json.jbuilder'

    actual_response = JSON.parse(@response.body)

    assert_equal actual_response["name"], 'GitHub'
  end

  test 'redirects from domain to canonical host name' do
    get api_v1_host_path(id: 'github.com')
    assert_response :moved_permanently
    assert_redirected_to api_v1_host_path(id: @host.name)
  end

  test 'redirects from domain preserves query parameters' do
    get api_v1_host_path(id: 'github.com'), params: { foo: 'bar' }
    assert_response :moved_permanently
    assert_redirected_to api_v1_host_path(id: @host.name, foo: 'bar')
  end

end