require "test_helper"

class ManifestTest < ActiveSupport::TestCase
  context 'associations' do
    should belong_to(:repository)
    should have_many(:dependencies)
  end
end
