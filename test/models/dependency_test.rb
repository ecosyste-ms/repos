require "test_helper"

class DependencyTest < ActiveSupport::TestCase
  context 'associations' do
    should belong_to(:repository)
    should belong_to(:manifest)
  end
end
