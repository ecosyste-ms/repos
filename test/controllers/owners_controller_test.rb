require 'test_helper'

class OwnersControllerTest < ActionDispatch::IntegrationTest
  setup do
    @host = Host.create(name: 'GitHub', url: 'https://github.com', kind: 'github')
    @owner = Owner.create(login: 'ecosyste-ms', host: @host)
    @hidden_owner = Owner.create(login: 'hidden-owner', host: @host, hidden: true)
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

  test 'get a hidden owner returns 404' do
    get host_owner_path(host_id: @host.name, id: 'hidden-owner')
    assert_response :not_found
  end

  test 'non-nullable sort columns omit null ordering' do
    %w[id created_at updated_at].each do |column|
      %w[asc desc].each do |order|
        sql = capture_ordered_repositories_query(sort: column, order: order)
        assert_match(/ORDER BY repositories\.#{column} #{order.upcase}/i, sql)
        refute_match(/NULLS LAST/i, sql)
      end
    end
  end

  test 'nullable sort columns keep null ordering' do
    %w[stargazers_count pushed_at last_synced_at].each do |column|
      %w[asc desc].each do |order|
        sql = capture_ordered_repositories_query(sort: column, order: order)
        assert_match(/ORDER BY repositories\.#{column} #{order.upcase} NULLS LAST/i, sql)
      end
    end
  end

  test 'unknown sort falls back to non-nullable updated_at' do
    sql = capture_ordered_repositories_query(sort: 'not_a_column', order: 'desc')
    assert_match(/ORDER BY repositories\.updated_at DESC/i, sql)
    refute_match(/NULLS LAST/i, sql)
  end

  def capture_ordered_repositories_query(params)
    queries = []
    callback = ->(*, payload) { queries << payload[:sql] if payload[:sql] =~ /FROM "repositories".*ORDER BY/im }
    ActiveSupport::Notifications.subscribed(callback, 'sql.active_record') do
      get host_owner_path(host_id: @host.name, id: 'ecosyste-ms'), params: params
    end
    assert_response :success
    assert_equal 1, queries.size, queries.inspect
    queries.first
  end

  test 'get a subgroup' do
    @repository = @host.repositories.create(full_name: 'ecosyste-ms/security/test', owner: 'ecosyste-ms', created_at: Time.now, updated_at: Time.now)
    get subgroup_host_owner_path(host_id: @host.name, id: 'ecosyste-ms', subgroup: 'security')
    assert_response :success
    assert_template 'owners/subgroup', file: 'owners/subgroup.html.erb'
  end
end