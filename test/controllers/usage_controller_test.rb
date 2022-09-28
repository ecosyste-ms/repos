require "test_helper"

class UsageControllerTest < ActionDispatch::IntegrationTest
  test "should get index" do
    get usage_index_url
    assert_response :success
  end

  test "should get show" do
    PackageUsage.create!(ecosystem: 'npm', name: 'lodash', dependents_count: 1)
    get usage_url('npm', 'lodash')
    assert_response :success
  end
end
