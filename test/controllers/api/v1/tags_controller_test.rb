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
end
