require 'test_helper'

class Api::V1::ReleasesControllerTest < ActionDispatch::IntegrationTest
  setup do
    @host = create(:host, name: 'GitHub')
    @repository = create(:repository, host: @host, full_name: 'user/repo')
    
    @release_v1 = create(:release, 
      repository: @repository,
      tag_name: 'v1.0.0',
      published_at: 2.days.ago
    )
    
    @release_v2 = create(:release,
      repository: @repository, 
      tag_name: 'v2.0.0',
      published_at: 1.day.ago
    )
  end

  test "should get index for valid repository" do
    get api_v1_host_repository_releases_path(@host.name, @repository.full_name)
    assert_response :success
    
    data = JSON.parse(@response.body)
    assert data.is_a?(Array)
    assert_equal 2, data.length
  end

  test "should return 404 for non-existent host" do
    get api_v1_host_repository_releases_path('NonExistentHost', @repository.full_name)
    assert_response :not_found
  end

  test "should return 404 for non-existent repository" do
    get api_v1_host_repository_releases_path(@host.name, 'user/nonexistent')
    assert_response :not_found
  end

  test "should order releases by published_at desc by default" do
    get api_v1_host_repository_releases_path(@host.name, @repository.full_name)
    assert_response :success
    
    data = JSON.parse(@response.body)
    release_tags = data.map { |r| r['tag_name'] }
    assert_equal ['v2.0.0', 'v1.0.0'], release_tags
  end

  test "should show individual release" do
    get api_v1_host_repository_release_path(@host.name, @repository.full_name, @release_v1.tag_name)
    assert_response :success
    
    data = JSON.parse(@response.body)
    assert data.key?('tag_name')
    assert_equal 'v1.0.0', data['tag_name']
  end

  test "should return 404 for non-existent release" do
    get api_v1_host_repository_release_path(@host.name, @repository.full_name, 'v999.0.0')
    assert_response :not_found
  end

  test "should include release attributes in index" do
    get api_v1_host_repository_releases_path(@host.name, @repository.full_name)
    assert_response :success
    
    data = JSON.parse(@response.body)
    release = data.first
    
    # Check required attributes
    assert release.key?('tag_name')
    assert release.key?('published_at')
    assert release.key?('name')
    assert release.key?('body')
    assert release.key?('draft')
    assert release.key?('prerelease')
  end

  test "should include release attributes in show" do
    get api_v1_host_repository_release_path(@host.name, @repository.full_name, @release_v1.tag_name)
    assert_response :success
    
    data = JSON.parse(@response.body)
    
    # Check required attributes
    assert data.key?('tag_name')
    assert data.key?('published_at')
    assert data.key?('name')
    assert data.key?('body')
    assert data.key?('draft')
    assert data.key?('prerelease')
  end

  test "should set proper cache headers for index" do
    get api_v1_host_repository_releases_path(@host.name, @repository.full_name)
    assert_response :success
    
    # Should have caching headers
    assert_not_nil @response.headers['Cache-Control']
    assert_includes @response.headers['Cache-Control'], 'public'
  end

  test "should set proper cache headers for show" do
    get api_v1_host_repository_release_path(@host.name, @repository.full_name, @release_v1.tag_name)
    assert_response :success
    
    # Should have caching headers
    assert_not_nil @response.headers['Cache-Control']
    assert_includes @response.headers['Cache-Control'], 'public'
  end
end