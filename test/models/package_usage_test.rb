require "test_helper"

class PackageUsageTest < ActiveSupport::TestCase
  context 'associations' do
    should have_many(:repository_usages)
    should have_many(:repositories).through(:repository_usages)
  end
end
