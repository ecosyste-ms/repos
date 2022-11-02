require "test_helper"

class OwnerTest < ActiveSupport::TestCase
  context 'associations' do
    should belong_to(:host)
  end
end
