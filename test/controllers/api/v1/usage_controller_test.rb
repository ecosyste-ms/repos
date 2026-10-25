require "test_helper"

class ApiV1UsageControllerTest < ActionDispatch::IntegrationTest
  self.use_transactional_tests = false

  test 'membership removals decrease API counts and invalidate conditional responses' do
    previous_generation = ENV['REPOSITORY_USAGE_GENERATION']
    previous_read_generation = ENV['REPOSITORY_USAGE_READ_GENERATION']
    ENV['REPOSITORY_USAGE_GENERATION'] = ENV['REPOSITORY_USAGE_READ_GENERATION'] = '1'
    previous_enabled = ENV['REPOSITORY_USAGE_WRITES_ENABLED']
    previous_ids = ENV['REPOSITORY_USAGE_REPOSITORY_IDS']
    repository = create(:repository, dependencies_parsed_at: Time.current)
    ENV['REPOSITORY_USAGE_WRITES_ENABLED'] = 'true'
    ENV['REPOSITORY_USAGE_REPOSITORY_IDS'] = repository.id.to_s
    manifest = create(:manifest, repository: repository)
    dependency = create(:dependency, repository: repository, manifest: manifest, ecosystem: 'npm', package_name: 'lodash')
    RepositoryUsageWorker.new.perform(repository.id)

    get api_v1_usage_url('npm', 'lodash')
    assert_response :success
    assert_equal 1, response.parsed_body['dependents_count']
    etag = response.headers['ETag']

    travel 2.seconds do
      dependency.destroy!
      repository.update_column(:usage_updated_at, Time.current)
      RepositoryUsageWorker.new.perform(repository.id)
    end
    get api_v1_usage_url('npm', 'lodash'), headers: { 'If-None-Match' => etag }
    assert_response :success
    assert_equal 0, response.parsed_body['dependents_count']
    assert_not_equal etag, response.headers['ETag']

    get api_v1_usage_url('npm', 'lodash'), headers: { 'If-None-Match' => response.headers['ETag'] }
    assert_response :not_modified
  ensure
    ENV['REPOSITORY_USAGE_GENERATION'] = previous_generation
    ENV['REPOSITORY_USAGE_READ_GENERATION'] = previous_read_generation
    ENV['REPOSITORY_USAGE_WRITES_ENABLED'] = previous_enabled
    ENV['REPOSITORY_USAGE_REPOSITORY_IDS'] = previous_ids
  end

  test "should get index" do
    get api_v1_usage_index_url
    assert_response :success
  end

  test 'switching count generation changes values ordering and cache validators without publication writes' do
    previous = ENV['REPOSITORY_USAGE_READ_GENERATION']
    ENV.delete('REPOSITORY_USAGE_READ_GENERATION')
    used = create(:package_usage, ecosystem: 'npm', name: 'used', key: 'npm:used', dependents_count: 1, repository_usages_count: 3, usage_count_generation: 7)
    unused = create(:package_usage, ecosystem: 'npm', name: 'unused', key: 'npm:unused', dependents_count: 99, repository_usages_count: 888)
    get api_v1_usage_url('npm', 'unused')
    assert_equal 99, response.parsed_body['dependents_count']
    etag, modified = response.headers.values_at('ETag', 'Last-Modified')
    get api_v1_ecosystem_usage_url('npm')
    ecosystem_etag = response.headers['ETag']
    assert_equal ['unused', 'used'], response.parsed_body.pluck('name')
    ENV['REPOSITORY_USAGE_READ_GENERATION'] = '7'
    get api_v1_usage_url('npm', 'unused'), headers: {'If-None-Match' => etag}
    assert_response :success
    assert_equal 0, response.parsed_body['dependents_count']
    assert_not_equal etag, response.headers['ETag']
    get api_v1_usage_url('npm', 'unused'), headers: {'If-Modified-Since' => modified}
    assert_response :success
    get api_v1_ecosystem_usage_url('npm'), headers: {'If-None-Match' => ecosystem_etag}
    assert_response :success
    assert_equal [['used', 3], ['unused', 0]], response.parsed_body.map { |row| row.values_at('name', 'dependents_count') }
    assert_equal [1, 99], [used, unused].map { |usage| usage.reload[:dependents_count] }
  ensure
    ENV['REPOSITORY_USAGE_READ_GENERATION'] = previous
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
