require 'test_helper'

class OwnersControllerTest < ActionDispatch::IntegrationTest
  setup do
    @host = Host.create(name: 'GitHub', url: 'https://github.com', kind: 'github')
    @owner = Owner.create(login: 'ecosyste-ms', host: @host)
    @repository = @host.repositories.create(full_name: 'ecosyste-ms/repos', owner: 'ecosyste-ms',created_at: Time.now, updated_at: Time.now)
  end

  test 'get owners' do 
    get host_owners_url(@host)
    assert_response :success
    assert_template 'owners/index', file: 'owners/index.html.erb'
  end

  test 'get an owner' do
    get host_owner_path(host_id: @host.name, id: 'ecosyste-ms')
    assert_response :success
    assert_template 'owners/show', file: 'owners/show.html.erb'
  end

  test 'get a subgroup' do
    @repository = @host.repositories.create(full_name: 'ecosyste-ms/security/test', owner: 'ecosyste-ms', created_at: Time.now, updated_at: Time.now)
    get subgroup_host_owner_path(host_id: @host.name, id: 'ecosyste-ms', subgroup: 'security')
    assert_response :success
    assert_template 'owners/subgroup', file: 'owners/subgroup.html.erb'
  end
end