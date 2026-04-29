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

  test 'gets global host stats' do
    @host.repositories.create!(full_name: 'ecosyste-ms/repos', owner: @visible_owner.login, stargazers_count: 10, forks_count: 2)
    @visible_owner.update!(repositories_count: 1, total_stars: 10)

    get api_v1_hosts_stats_path
    assert_response :success

    actual_response = JSON.parse(@response.body)
    assert_equal 1, actual_response['hosts_count']
    assert_equal 'ecosyste-ms/repos', actual_response['top_repositories'].first['full_name']
    assert_equal @visible_owner.login, actual_response['top_owners'].first['login']
  end

  test 'gets stats for a host' do
    @host.repositories.create!(full_name: 'ecosyste-ms/repos', owner: @visible_owner.login, stargazers_count: 10, forks_count: 2)
    @visible_owner.update!(repositories_count: 1, total_stars: 10)

    get stats_api_v1_host_path(id: @host.name)
    assert_response :success

    actual_response = JSON.parse(@response.body)
    assert_equal @host.name, actual_response['host']
    assert_equal 1, actual_response['repositories_count']
    assert_equal 'ecosyste-ms/repos', actual_response['top_repositories'].first['full_name']
  end

end