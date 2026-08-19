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
