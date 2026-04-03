require 'test_helper'

class ParseTagDependenciesWorkerTest < ActiveSupport::TestCase
  context '#perform' do
    should 'call parse_dependencies on tag' do
      host = create(:host)
      repository = create(:repository, host: host)
      tag = create(:tag, repository: repository)

      Tag.any_instance.expects(:parse_dependencies).once

      worker = ParseTagDependenciesWorker.new
      worker.perform(tag.id)
    end

    should 'handle non-existent tag gracefully' do
      worker = ParseTagDependenciesWorker.new

      assert_nothing_raised do
        worker.perform(999999)
      end
    end

    should 'eager load manifests but not dependencies' do
      host = create(:host)
      repository = create(:repository, host: host)
      tag = create(:tag, repository: repository)
      create(:manifest, tag: tag, repository: nil)

      Tag.any_instance.stubs(:parse_dependencies)

      queries = []
      callback = lambda { |_name, _start, _finish, _id, payload|
        queries << payload[:sql] if payload[:sql].present?
      }

      ActiveSupport::Notifications.subscribed(callback, "sql.active_record") do
        ParseTagDependenciesWorker.new.perform(tag.id)
      end

      manifest_queries = queries.select { |q| q.include?('manifests') }
      dependency_queries = queries.select { |q| q.include?('dependencies') }
      assert manifest_queries.any?, "Should eager load manifests"
      assert_empty dependency_queries, "Should not eager load dependencies"
    end
  end
end
