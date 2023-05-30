require "test_helper"

class ManifestTest < ActiveSupport::TestCase
  context 'associations' do
    should belong_to(:repository).optional
    should belong_to(:tag).optional
    should have_many(:dependencies)
  end
end
