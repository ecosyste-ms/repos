require "test_helper"

class PackageUsageTest < ActiveSupport::TestCase
  context 'associations' do
    should have_many(:repository_usages)
    should have_many(:repositories).through(:repository_usages)
  end

  test "ecosystem_counts caches the grouped counts" do
    original_cache = Rails.cache
    Rails.cache = ActiveSupport::Cache::MemoryStore.new
    create(:package_usage, ecosystem: 'npm', name: 'a')
    create(:package_usage, ecosystem: 'npm', name: 'b')
    create(:package_usage, ecosystem: 'cargo', name: 'c')
    assert_equal [['npm', 2], ['cargo', 1]], PackageUsage.ecosystem_counts
    create(:package_usage, ecosystem: 'cargo', name: 'd')
    create(:package_usage, ecosystem: 'cargo', name: 'e')
    assert_equal [['npm', 2], ['cargo', 1]], PackageUsage.ecosystem_counts
    assert_equal [['cargo', 3], ['npm', 2]], PackageUsage.ecosystem_counts(force: true)
  ensure
    Rails.cache = original_cache
  end
end
