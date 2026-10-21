require "test_helper"

class ApiV1UsageControllerTest < ActionDispatch::IntegrationTest
  test "should get index" do
    get api_v1_usage_index_url
    assert_response :success
  end

  test "should get ecosystem" do
    PackageUsage.create!(ecosystem: 'npm', name: 'lodash', key: "npm:lodash", dependents_count: 1)
    get api_v1_ecosystem_usage_url('npm')
    assert_response :success
  end

  test "ecosystem handles missing timestamps alongside dated usages" do
    older = create(:package_usage, ecosystem: 'packagist', name: 'symfony/console', dependents_count: 30, updated_at: 2.days.ago)
    undated = create(:package_usage, ecosystem: 'packagist', name: 'monolog/monolog', dependents_count: 20)
    undated.update_columns(created_at: nil, updated_at: nil)
    newest = create(:package_usage, ecosystem: 'packagist', name: 'guzzlehttp/guzzle', dependents_count: 10, updated_at: 1.day.ago)

    get '/api/v1/usage/packagist'

    assert_response :success
    assert_equal [older.name, undated.name, newest.name], response.parsed_body.pluck('name')
    assert_equal newest.updated_at.httpdate, response.headers['Last-Modified']
    assert_includes response.headers['Cache-Control'], 'public'
    assert_predicate response.headers['ETag'], :present?

    get '/api/v1/usage/packagist', headers: { 'If-None-Match' => response.headers['ETag'] }

    assert_response :not_modified
  end

  test "ecosystem handles only undated usages" do
    usages = %w[symfony/console monolog/monolog].map do |name|
      usage = create(:package_usage, ecosystem: 'packagist', name: name)
      usage.update_columns(created_at: nil, updated_at: nil)
      usage
    end

    get '/api/v1/usage/packagist'

    assert_response :success
    assert_equal usages.map(&:name).sort, response.parsed_body.pluck('name').sort
    assert_nil response.headers['Last-Modified']
    assert_predicate response.headers['ETag'], :present?
  end

  test "ecosystem handles an empty page" do
    get '/api/v1/usage/packagist'

    assert_response :success
    assert_equal [], response.parsed_body
    assert_nil response.headers['Last-Modified']
  end


  test "should get show" do
    PackageUsage.create!(ecosystem: 'npm', name: 'lodash', key: "npm:lodash", dependents_count: 1)
    get api_v1_usage_url('npm', 'lodash')
    assert_response :success
  end

  test "invalid dependent repository sort falls back to id ascending" do
    usage = create(:package_usage, ecosystem: 'npm', name: 'lodash')
    repositories = create_list(:repository, 2)
    usage.repositories << repositories.reverse

    get api_v1_usage_dependent_repositories_url('npm', 'lodash'), params: { sort: 'cast(uuid as integer)' }
    assert_response :success

    actual_response = JSON.parse(@response.body)

    assert_equal repositories.map(&:id).sort, actual_response.pluck('id')
  end
end
