require 'test_helper'

class HostsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @host = Host.create(name: 'GitHub', url: 'https://github.com', kind: 'github')
  end

  test 'get a host' do
    get host_path(id: @host.name)
    assert_response :success
    assert_template 'hosts/show', file: 'hosts/show.html.erb'
  end
end