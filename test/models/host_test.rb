require "test_helper"

class HostTest < ActiveSupport::TestCase
  context 'associations' do
    should have_many(:repositories)
  end
end
