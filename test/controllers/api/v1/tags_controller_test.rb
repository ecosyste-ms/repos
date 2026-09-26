require 'test_helper'

class ApiV1TagsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @host = Host.create(name: 'GitHub', url: 'https://github.com', kind: 'github')
    @repository = @host.repositories.create(full_name: 'ecosyste-ms/repos', created_at: Time.now, updated_at: Time.now)
    @tag = @repository.tags.create(name: '1.0.0', sha: 'deadbeef')
  end

  test 'list tags for a repository' do
    get api_v1_host_repository_tags_path(host_id: @host.name, repository_id: @repository.full_name)
    assert_response :success
    assert_template 'tags/index', file: 'repositories/tags.json.jbuilder'
    
    actual_response = JSON.parse(@response.body)

    assert_equal actual_response.length, 1
  end

  test 'invalid tag sort falls back to published at descending' do
    @tag.update!(published_at: 2.days.ago)
    newer_tag = @repository.tags.create!(name: '2.0.0', sha: 'feedface', published_at: 1.day.ago)

    get api_v1_host_repository_tags_path(host_id: @host.name, repository_id: @repository.full_name), params: { sort: 'cast(uuid as integer)' }
    assert_response :success

    actual_response = JSON.parse(@response.body)

    assert_equal [newer_tag.name, @tag.name], actual_response.pluck('name')
  end

  test 'published_at sort puts undated tags last and matches the index ordering' do
    @tag.update!(published_at: 2.days.ago)
    newer = @repository.tags.create!(name: '2.0.0', sha: 'feedface', published_at: 1.day.ago)
    undated = @repository.tags.create!(name: '3.0.0', sha: 'cafebabe')

    sql = capture_ordered_tags_query
    assert_match(/ORDER BY tags\.published_at DESC NULLS LAST/i, sql)
    assert_equal [newer.name, @tag.name, undated.name], JSON.parse(@response.body).pluck('name')
  end

  test 'non-nullable tag sort columns omit null ordering' do
    sql = capture_ordered_tags_query(sort: 'created_at', order: 'asc')
    assert_match(/ORDER BY tags\.created_at ASC/i, sql)
    refute_match(/NULLS LAST/i, sql)
  end

  def capture_ordered_tags_query(params = {})
    queries = []
    callback = ->(*, payload) { queries << payload[:sql] if payload[:sql] =~ /FROM "tags".*ORDER BY/im }
    ActiveSupport::Notifications.subscribed(callback, 'sql.active_record') do
      get api_v1_host_repository_tags_path(host_id: @host.name, repository_id: @repository.full_name), params: params
    end
    assert_response :success
    assert_equal 1, queries.size, queries.inspect
    queries.first
  end

  test 'falls back to repository show when full_name ends in tags' do
    repo = @host.repositories.create!(full_name: 'group/subgroup/tags', created_at: Time.now, updated_at: Time.now)

    get "/api/v1/hosts/#{@host.name}/repositories/#{repo.full_name}"
    assert_response :success

    body = JSON.parse(@response.body)
    assert_equal 'group/subgroup/tags', body['full_name']
  end

  test 'still 404s when neither the shorter nor the full path exists' do
    Host.any_instance.expects(:sync_repository_async).with('missing/owner')

    get api_v1_host_repository_tags_path(host_id: @host.name, repository_id: 'missing/owner')
    assert_response :not_found
  end
end
