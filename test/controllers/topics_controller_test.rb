require 'test_helper'

class TopicsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @host = create(:host, name: 'GitHub', url: 'https://github.com', kind: 'github')
    @owner = create(:owner, host: @host, login: 'ecosyste-ms')
    @repository = create(:repository, host: @host, full_name: 'ecosyste-ms/repos', owner: @owner.login, topics: ['ruby', 'rails'])
  end

  test 'get blocked topic returns 404' do
    ENV['BLOCKED_TOPICS'] = 'malwarebytes-unlocked-version,premiere-crack-2023'
    get topic_path(id: 'malwarebytes-unlocked-version')
    assert_response :not_found
    ENV.delete('BLOCKED_TOPICS')
  end

  test 'get non-blocked topic returns success' do
    get topic_path(id: 'ruby')
    assert_response :success
  end

  test 'topics index excludes blocked topics' do
    blocked_repo = create(:repository, host: @host, full_name: 'test/blocked', owner: @owner.login, topics: ['malwarebytes-unlocked-version', 'good-topic'])
    ENV['BLOCKED_TOPICS'] = 'malwarebytes-unlocked-version,premiere-crack-2023'

    get topics_path
    assert_response :success

    topic_names = assigns(:topics).map { |t| t[0] }
    assert_not_includes topic_names, 'malwarebytes-unlocked-version'
    assert_not_includes topic_names, 'premiere-crack-2023'

    ENV.delete('BLOCKED_TOPICS')
  end

  test 'host topics index excludes blocked topics' do
    blocked_repo = create(:repository, host: @host, full_name: 'test/blocked', owner: @owner.login, topics: ['download-free-dxo-photolab', 'good-topic'])
    ENV['BLOCKED_TOPICS'] = 'download-free-dxo-photolab'

    get topics_host_path(id: @host.name)
    assert_response :success

    topic_names = assigns(:topics).map { |t| t[0] }
    assert_not_includes topic_names, 'download-free-dxo-photolab'

    ENV.delete('BLOCKED_TOPICS')
  end
end
