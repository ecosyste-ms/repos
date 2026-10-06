require 'test_helper'

class UpdateMetadataFilesWorkerTest < ActiveSupport::TestCase
  test 'persists accessibility file metadata from the GitHub tree' do
    repository = create(:github_repository, default_branch: 'main', metadata: {})
    Hosts::Github.any_instance.stubs(:fetch_random_token).returns(nil)

    request = stub_request(:get, "https://api.github.com/repos/#{repository.full_name}/git/trees/main")
      .with(query: { recursive: 'true' })
      .to_return(status: 200, headers: { 'Content-Type' => 'application/json' }, body: {
        sha: 'abc123',
        truncated: false,
        tree: [
          { path: '.github', type: 'tree', mode: '040000', sha: 'def456' },
          { path: '.github/ACCESSIBILITY.md', type: 'blob', mode: '100644', sha: 'fed321' },
          { path: 'README.md', type: 'blob', mode: '100644', sha: 'cba654' }
        ]
      }.to_json)

    UpdateMetadataFilesWorker.new.perform(repository.id)

    assert_requested request
    assert_equal '.github/ACCESSIBILITY.md', repository.reload.metadata['files']['accessibility']
    assert_equal 'README.md', repository.metadata['files']['readme']
  end
end
