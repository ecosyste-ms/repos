require "test_helper"

class TagTest < ActiveSupport::TestCase
  context 'associations' do
    should belong_to(:repository)
  end
end
