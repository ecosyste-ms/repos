require 'test_helper'

class RepositoriesControllerTest < ActionDispatch::IntegrationTest
  setup do
    @host = Host.create(name: 'GitHub', url: 'https://github.com', kind: 'github')
    @owner = Owner.create(login: 'ecosyste-ms', host: @host)
    @hidden_owner = Owner.create(login: 'hidden-owner', host: @host, hidden: true)
    @repository = @host.repositories.create(full_name: 'ecosyste-ms/repos', owner: 'ecosyste-ms', created_at: Time.now, updated_at: Time.now)
    @hidden_repository = @host.repositories.create(full_name: 'hidden-owner/repo', owner: 'hidden-owner', created_at: Time.now, updated_at: Time.now)
  end

  test 'get a repository for a host' do
    get host_repository_path(host_id: @host.name, id: @repository.full_name)
    assert_response :success
    assert_template 'repositories/show', file: 'repositories/show.html.erb'
  end

  test 'get a repository with hidden owner returns 404' do
    get host_repository_path(host_id: @host.name, id: @hidden_repository.full_name)
    assert_response :not_found
  end

  test 'get dependencies for repository with hidden owner returns 404' do
    get dependencies_host_repository_path(host_id: @host.name, id: @hidden_repository.full_name)
    assert_response :not_found
  end

  test 'get readme for repository with hidden owner returns 404' do
    get readme_host_repository_path(host_id: @host.name, id: @hidden_repository.full_name)
    assert_response :not_found
  end
end