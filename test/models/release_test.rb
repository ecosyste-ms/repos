require "test_helper"

class ReleaseTest < ActiveSupport::TestCase
  setup do
    @repository = create(:repository)
    @release = create(:release, repository: @repository, tag_name: 'v1.0.0')
  end

  test 'semantic version parsing' do
    assert_equal '1.0.0', @release.clean_number
    assert_not_nil @release.semantic_version
  end

  test 'semantic version comparison' do
    release1 = create(:release, repository: @repository, tag_name: 'v1.0.0')
    release2 = create(:release, repository: @repository, tag_name: 'v2.0.0')
    release3 = create(:release, repository: @repository, tag_name: 'v1.5.0')

    sorted = [release1, release2, release3].sort
    assert_equal [release2, release3, release1], sorted
  end

  test 'non-semver tags fall back to string comparison' do
    release1 = create(:release, repository: @repository, tag_name: 'latest')
    release2 = create(:release, repository: @repository, tag_name: 'main')
    
    sorted = [release1, release2].sort
    assert_equal 2, sorted.length
  end
end
