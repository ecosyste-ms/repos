require 'test_helper'

class HostsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @host = Host.create(name: 'GitHub', url: 'https://github.com', kind: 'github')
    # Create a repository with topics for testing topic routes
    @repo = @host.repositories.create!(
      full_name: 'test/repo',
      owner: 'test',
      created_at: Time.now,
      updated_at: Time.now,
      last_synced_at: Time.now,
      topics: ['ruby', 'Node.js', 'HTML/CSS', 'some/ip']
    )
  end

  test 'get a host' do
    get host_path(id: @host.name)
    assert_response :success
    assert_template 'hosts/show', file: 'hosts/show.html.erb'
  end

  test 'topic route with simple topic' do
    get topic_host_path(id: @host.name, topic: 'ruby')
    assert_response :success
    assert_equal 'hosts', controller.controller_name
    assert_equal 'topic', controller.action_name
  end

  test 'topic route with topic containing dots' do
    get topic_host_path(id: @host.name, topic: 'Node.js')
    assert_response :success
    assert_equal 'hosts', controller.controller_name
    assert_equal 'topic', controller.action_name
    assert_equal 'Node.js', controller.params[:topic]
  end

  test 'topic route with topic containing forward slashes' do
    get topic_host_path(id: @host.name, topic: 'HTML/CSS')
    assert_response :success
    assert_equal 'hosts', controller.controller_name
    assert_equal 'topic', controller.action_name
    assert_equal 'HTML/CSS', controller.params[:topic]
  end

  test 'topic route with complex topic' do
    get topic_host_path(id: @host.name, topic: 'some/ip')
    assert_response :success
    assert_equal 'hosts', controller.controller_name
    assert_equal 'topic', controller.action_name
    assert_equal 'some/ip', controller.params[:topic]
  end

  test 'repository route does not match topic route' do
    # This URL should go to repositories#show, not hosts#topic
    get "/hosts/#{@host.name}/repositories/FAvO%2Fwera"
    assert_equal 'repositories', controller.controller_name
    assert_equal 'show', controller.action_name
    assert_equal 'FAvO/wera', controller.params[:id]
  end

  test 'repository route with encoded slash does not match topic route' do
    get "/hosts/#{@host.name}/repositories/randzellcura%2Fcapstone1"
    assert_equal 'repositories', controller.controller_name
    assert_equal 'show', controller.action_name
    assert_equal 'randzellcura/capstone1', controller.params[:id]
  end

  test 'repository dependencies route does not match topic route' do
    get "/hosts/#{@host.name}/repositories/ackheron%2Fmedium/dependencies"
    assert_equal 'repositories', controller.controller_name
    assert_equal 'dependencies', controller.action_name
    assert_equal 'ackheron/medium', controller.params[:id]
  end

  test 'repository releases route does not match topic route' do
    get "/hosts/#{@host.name}/repositories/FAvO%2Fwera/releases"
    assert_equal 'repositories', controller.controller_name
    assert_equal 'releases', controller.action_name
    assert_equal 'FAvO/wera', controller.params[:id]
  end

  test 'topics index excludes blocked topics' do
    blocked_repo = @host.repositories.create!(
      full_name: 'test/blocked',
      owner: 'test',
      created_at: Time.now,
      updated_at: Time.now,
      last_synced_at: Time.now,
      topics: ['malwarebytes-unlocked-version', 'good-topic']
    )
    ENV['BLOCKED_TOPICS'] = 'malwarebytes-unlocked-version,premiere-crack-2023'

    get topics_host_path(id: @host.name)
    assert_response :success

    topic_names = assigns(:topics).map { |t| t[0] }
    assert_not_includes topic_names, 'malwarebytes-unlocked-version'
    assert_not_includes topic_names, 'premiere-crack-2023'

    ENV.delete('BLOCKED_TOPICS')
  end

  test 'blocked topic page returns 404' do
    blocked_repo = @host.repositories.create!(
      full_name: 'test/blocked',
      owner: 'test',
      created_at: Time.now,
      updated_at: Time.now,
      last_synced_at: Time.now,
      topics: ['download-free-dxo-photolab']
    )
    ENV['BLOCKED_TOPICS'] = 'download-free-dxo-photolab'

    get topic_host_path(id: @host.name, topic: 'download-free-dxo-photolab')
    assert_response :not_found

    ENV.delete('BLOCKED_TOPICS')
  end

  test 'non-blocked topic page returns success' do
    get topic_host_path(id: @host.name, topic: 'ruby')
    assert_response :success
  end
end