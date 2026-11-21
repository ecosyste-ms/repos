require "test_helper"

class UsageControllerTest < ActionDispatch::IntegrationTest
  test "should get index" do
    get usage_index_url
    assert_response :success
  end

  test "should get ecosystem" do
    PackageUsage.create!(ecosystem: 'npm', name: 'lodash', key: "npm:lodash", dependents_count: 1)
    get ecosystem_usage_url('npm')
    assert_response :success
  end


  test "should get show" do
    PackageUsage.create!(ecosystem: 'npm', name: 'lodash', key: "npm:lodash", dependents_count: 1)
    get usage_url('npm', 'lodash')
    assert_response :success
  end

  test "show renders a dependency row" do
    PackageUsage.create!(ecosystem: 'npm', name: 'lodash', key: "npm:lodash", dependents_count: 1)
    repository = create(:repository)
    manifest = create(:manifest, repository: repository)
    create(:dependency, repository: repository, manifest: manifest, ecosystem: 'npm', package_name: 'lodash', requirements: '^4.17.0')
    get usage_url('npm', 'lodash')
    assert_response :success
    assert_select "#repository_#{repository.id}"
    assert_select 'li', text: /\^4\.17\.0/
  end

  test "show returns an empty page beyond the pagination cap" do
    PackageUsage.create!(ecosystem: 'npm', name: 'lodash', key: "npm:lodash", dependents_count: 1)
    get usage_url('npm', 'lodash', page: UsageController::MAX_PAGES + 1)
    assert_response :success
    assert_equal 0, assigns(:dependencies).size
  end
end
