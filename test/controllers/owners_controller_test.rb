require 'test_helper'

class OwnersControllerTest < ActionDispatch::IntegrationTest
  setup do
    @host = Host.create(name: 'GitHub', url: 'https://github.com', kind: 'github')
    @repository = @host.repositories.create(full_name: 'ecosyste-ms/repos', owner: 'ecosyste-ms')
  end

  test 'get an owner' do
    get host_owner_path(host_id: @host.name, id: 'ecosyste-ms')
    assert_response :success
    assert_template 'owners/show', file: 'owners/show.html.erb'
  end
end