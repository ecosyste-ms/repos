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

    should 'eager load manifests but not dependencies' do
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

      manifest_queries = queries.select { |q| q.include?('manifests') }
      dependency_queries = queries.select { |q| q.include?('dependencies') }
      assert manifest_queries.any?, "Should eager load manifests"
      assert_empty dependency_queries, "Should not eager load dependencies"
    end
  end
end
