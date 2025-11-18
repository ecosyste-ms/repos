require "test_helper"

class RegistryTest < ActiveSupport::TestCase
  context 'EcosystemApiClient concern' do
    should 'respond to ecosystem_connection as a class method' do
      assert Registry.respond_to?(:ecosystem_connection)
    end
  end

  context 'class methods' do
    should 'have sync_all method' do
      assert Registry.respond_to?(:sync_all)
    end

    should 'have find_by_ecosystem method' do
      assert Registry.respond_to?(:find_by_ecosystem)
    end

    should 'have ecosystems method' do
      assert Registry.respond_to?(:ecosystems)
    end
  end
end
