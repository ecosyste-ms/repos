require "test_helper"

class RepositoryUsageTest < ActiveSupport::TestCase
  context 'associations' do
    should belong_to(:repository)
    should belong_to(:package_usage)
  end

  context 'validations' do
    should validate_presence_of(:repository_id)
    should validate_presence_of(:package_usage_id)
  end

  context '.from_repository' do
    setup do
      skip "TODO(DB_PERF): RepositoryUsage disabled 2026-01-10"
      @repository = create(:repository, dependencies_parsed_at: Time.now)
      @manifest = create(:manifest, repository: @repository)
    end

    should 'create repository usages for dependencies' do
      dep1 = create(:dependency, manifest: @manifest, repository: @repository, ecosystem: 'npm', package_name: 'lodash')
      dep2 = create(:dependency, manifest: @manifest, repository: @repository, ecosystem: 'npm', package_name: 'express')

      assert_difference 'RepositoryUsage.count', 2 do
        RepositoryUsage.from_repository(@repository)
      end

      @repository.reload
      assert_not_nil @repository.usage_last_calculated
    end

    should 'deduplicate dependencies across manifests' do
      manifest2 = create(:manifest, repository: @repository, filepath: 'other/package.json')
      create(:dependency, manifest: @manifest, repository: @repository, ecosystem: 'npm', package_name: 'lodash')
      create(:dependency, manifest: manifest2, repository: @repository, ecosystem: 'npm', package_name: 'lodash')

      assert_difference 'RepositoryUsage.count', 1 do
        RepositoryUsage.from_repository(@repository)
      end
    end

    should 'skip repositories without dependencies_parsed_at' do
      @repository.update_column(:dependencies_parsed_at, nil)

      assert_no_difference 'RepositoryUsage.count' do
        RepositoryUsage.from_repository(@repository)
      end
    end

    should 'clear existing usages before recalculating' do
      dep = create(:dependency, manifest: @manifest, repository: @repository, ecosystem: 'npm', package_name: 'lodash')
      RepositoryUsage.from_repository(@repository)

      assert_equal 1, RepositoryUsage.where(repository: @repository).count

      dep.destroy
      create(:dependency, manifest: @manifest, repository: @repository, ecosystem: 'npm', package_name: 'express')
      create(:dependency, manifest: @manifest, repository: @repository, ecosystem: 'npm', package_name: 'react')
      RepositoryUsage.from_repository(@repository)

      assert_equal 2, RepositoryUsage.where(repository: @repository).count
    end

    should 'reuse existing package_usages' do
      existing_pu = create(:package_usage, ecosystem: 'npm', name: 'lodash', key: 'npm:lodash')
      create(:dependency, manifest: @manifest, repository: @repository, ecosystem: 'npm', package_name: 'lodash')

      assert_no_difference 'PackageUsage.count' do
        RepositoryUsage.from_repository(@repository)
      end

      usage = RepositoryUsage.find_by(repository: @repository)
      assert_equal existing_pu.id, usage.package_usage_id
    end
  end
end
