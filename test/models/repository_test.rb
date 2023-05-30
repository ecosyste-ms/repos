require "test_helper"

class RepositoryTest < ActiveSupport::TestCase
  context 'associations' do
    should belong_to(:host)
    should have_many(:manifests)
    should have_many(:tags)
  end
end
