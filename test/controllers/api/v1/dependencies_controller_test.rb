require 'test_helper'

class Api::V1::DependenciesControllerTest < ActionDispatch::IntegrationTest
  setup do
    @host = create(:host)
    @repository = create(:repository, host: @host)
    @package_usage = create(:package_usage, ecosystem: 'npm', name: 'react')
    
    @manifest = create(:manifest, repository: @repository)
    @dependency = create(:dependency, 
      manifest: @manifest,
      repository: @repository,
      ecosystem: 'npm',
      package_name: 'react'
    )
  end

  test "should get index for valid package" do
    get api_v1_usage_dependencies_path(ecosystem: 'npm', name: 'react')
    assert_response :success
    
    data = JSON.parse(@response.body)
    assert data.is_a?(Array)
    assert data.length > 0
  end

  test "should return 404 for non-existent package" do
    get api_v1_usage_dependencies_path(ecosystem: 'npm', name: 'nonexistent-package')
    assert_response :not_found
  end

  test "should include dependency attributes" do
    get api_v1_usage_dependencies_path(ecosystem: 'npm', name: 'react')
    assert_response :success
    
    data = JSON.parse(@response.body)
    dependency = data.first
    
    # Check required attributes
    assert dependency.key?('id')
    assert dependency.key?('ecosystem')
    assert dependency.key?('package_name')
    assert dependency.key?('requirements')
    assert dependency.key?('kind')
    assert dependency.key?('repository')
    assert dependency.key?('manifest')
  end

  test "should set proper cache headers" do
    get api_v1_usage_dependencies_path(ecosystem: 'npm', name: 'react')
    assert_response :success
    
    # Should have caching headers
    assert_not_nil @response.headers['Cache-Control']
    assert_includes @response.headers['Cache-Control'], 'public'
  end

  test "should handle empty results gracefully" do
    @dependency.destroy
    
    get api_v1_usage_dependencies_path(ecosystem: 'npm', name: 'react')
    assert_response :success
    
    data = JSON.parse(@response.body)
    assert data.is_a?(Array)
    assert_equal [], data
  end
end