require 'test_helper'

class ParseDependenciesWorkerTest < ActiveSupport::TestCase
  context '#perform' do
    should 'call parse_dependencies on repository' do
      host = create(:host)
      repository = create(:repository, host: host)

      Repository.any_instance.expects(:parse_dependencies).once

      worker = ParseDependenciesWorker.new
      worker.perform(repository.id)
    end

    should 'handle non-existent repository gracefully' do
      worker = ParseDependenciesWorker.new

      assert_nothing_raised do
        worker.perform(999999)
      end
    end

    should 'not eager load manifests and dependencies' do
      host = create(:host)
      repository = create(:repository, host: host)
      manifest = create(:manifest, repository: repository)
      create(:dependency, repository: repository, manifest: manifest)

      Repository.any_instance.stubs(:parse_dependencies)

      queries = []
      callback = lambda { |_name, _start, _finish, _id, payload|
        queries << payload[:sql] if payload[:sql].present?
      }

      ActiveSupport::Notifications.subscribed(callback, "sql.active_record") do
        ParseDependenciesWorker.new.perform(repository.id)
      end

      eager_load_queries = queries.select { |q| q.include?('manifests') || q.include?('dependencies') }
      assert_empty eager_load_queries, "Should not eager load manifests or dependencies"
    end
  end
end
