require 'test_helper'

class ReadmeMetadataTest < ActiveSupport::TestCase
  test 'metadata worker stores the canonical README from an unordered GitHub tree' do
    repository = create(:github_repository, default_branch: 'main', metadata: {})
    stub_request(:get, "https://api.github.com/repos/#{repository.full_name}/git/trees/main?recursive=true")
      .to_return(headers: { 'Content-Type' => 'application/json' }, body: {
        tree: %w[README-ja.md README-ko.md README.md].map { |path| { path: path, type: 'blob' } }
      }.to_json)

    UpdateMetadataFilesWorker.new.perform(repository.id)

    assert_equal 'README.md', repository.reload.metadata.dig('files', 'readme')
  end
end
