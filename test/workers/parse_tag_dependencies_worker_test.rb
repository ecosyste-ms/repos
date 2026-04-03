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

    should 'not eager load manifests and dependencies' do
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

      eager_load_queries = queries.select { |q| q.include?('manifests') || q.include?('dependencies') }
      assert_empty eager_load_queries, "Should not eager load manifests or dependencies"
    end
  end
end
