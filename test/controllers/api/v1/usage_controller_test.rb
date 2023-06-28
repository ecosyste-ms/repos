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
end
