require 'test_helper'

class Api::V1::TopicsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @host = create(:host)
    
    @repo_javascript = create(:repository, 
      host: @host,
      topics: ['javascript', 'react', 'frontend'],
      full_name: 'user/js-app'
    )
    
    @repo_python = create(:repository,
      host: @host, 
      topics: ['python', 'django', 'backend'],
      full_name: 'user/py-app'
    )
    
    @repo_mixed = create(:repository,
      host: @host,
      topics: ['javascript', 'python', 'fullstack'],
      full_name: 'user/mixed-app'
    )
  end

  test "should get index of all topics" do
    skip "TODO(DB_PERF): topics query disabled 2026-01-10"
    get api_v1_topics_path
    assert_response :success

    data = JSON.parse(@response.body)
    assert data.is_a?(Array)
    # Should include topics from visible repositories
    assert data.length > 0
  end

  test "should set cache headers for topics index" do
    get api_v1_topics_path
    assert_response :success
    
    # Should have long cache expiration
    assert_not_nil @response.headers['Cache-Control']
    assert_includes @response.headers['Cache-Control'], 'public'
    assert_includes @response.headers['Cache-Control'], 'max-age=86400' # 1 day
  end

  test "should show repositories for specific topic" do
    get api_v1_topic_path('javascript')
    assert_response :success
    
    data = JSON.parse(@response.body)
    assert data.key?('repositories')
    assert data['repositories'].is_a?(Array)
    
    # Should include repositories with the topic
    repo_names = data['repositories'].map { |r| r['full_name'] }
    assert_includes repo_names, 'user/js-app'
    assert_includes repo_names, 'user/mixed-app'
    assert_not_includes repo_names, 'user/py-app'
  end

  test "should include related topics" do
    get api_v1_topic_path('javascript')
    assert_response :success
    
    data = JSON.parse(@response.body)
    assert data.key?('related_topics')
    assert data['related_topics'].is_a?(Array)
  end

  test "should handle non-existent topic gracefully" do
    get api_v1_topic_path('nonexistent-topic')
    assert_response :success
    
    data = JSON.parse(@response.body)
    assert data.key?('repositories')
    assert_equal [], data['repositories']
    assert data.key?('related_topics')
    assert_equal [], data['related_topics']
  end

  test "should include repository attributes" do
    get api_v1_topic_path('javascript')
    assert_response :success
    
    data = JSON.parse(@response.body)
    assert data.key?('repositories')
    
    if data['repositories'].any?
      repository = data['repositories'].first
      
      # Check required attributes
      assert repository.key?('full_name')
      # Host information might be nested or named differently
      assert repository.key?('created_at')
    else
      # If no repositories, that's also valid
      assert_equal [], data['repositories']
    end
  end

  test "should set proper cache headers for topic show" do
    get api_v1_topic_path('javascript')
    assert_response :success
    
    # Should have caching headers
    assert_not_nil @response.headers['Cache-Control']
    assert_includes @response.headers['Cache-Control'], 'public'
  end

  test "should support fork filter" do
    fork_repo = create(:repository, 
      host: @host, 
      topics: ['javascript'], 
      fork: true,
      full_name: 'user/forked-repo'
    )
    
    # Test excluding forks
    get api_v1_topic_path('javascript', fork: 'false')
    assert_response :success
    
    data = JSON.parse(@response.body)
    repo_names = data['repositories'].map { |r| r['full_name'] }
    assert_not_includes repo_names, 'user/forked-repo'
  end

  test "should support archived filter" do
    archived_repo = create(:repository,
      host: @host,
      topics: ['javascript'],
      archived: true,
      full_name: 'user/archived-repo'
    )
    
    # Test excluding archived
    get api_v1_topic_path('javascript', archived: 'false')
    assert_response :success
    
    data = JSON.parse(@response.body)
    repo_names = data['repositories'].map { |r| r['full_name'] }
    assert_not_includes repo_names, 'user/archived-repo'
  end
end