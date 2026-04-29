require "test_helper"

class Hosts::SourceforgeTest < ActiveSupport::TestCase
  setup do
    @host = create(:host, name: 'SourceForge', url: 'https://sourceforge.net', kind: 'sourceforge')
    @sourceforge = Hosts::Sourceforge.new(@host)
  end

  should 'map public project metadata to repository attributes' do
    stub_request(:get, "https://sourceforge.net/rest/p/sevenzip/")
      .to_return(
        status: 200,
        headers: { 'Content-Type' => 'application/json' },
        body: {
          '_id' => '50c218025fcbc909b58b271b',
          'shortname' => 'sevenzip',
          'name' => '7-Zip',
          'private' => false,
          'short_description' => 'A file archiver',
          'summary' => '7-Zip summary',
          'external_homepage' => 'https://www.7-zip.org/',
          'creation_date' => '2000-01-01',
          'last_updated' => '2026-04-01T00:00:00Z',
          'icon_url' => 'https://sourceforge.net/p/sevenzip/icon',
          'labels' => ['compression', 'archive']
        }.to_json
      )

    repo = @sourceforge.fetch_repository('sevenzip')

    assert_equal '50c218025fcbc909b58b271b', repo[:uuid]
    assert_equal 'sevenzip', repo[:full_name]
    assert_equal 'sevenzip', repo[:owner]
    assert_equal 'A file archiver', repo[:description]
    assert_equal 'https://www.7-zip.org/', repo[:homepage]
    assert_equal false, repo[:private]
    assert_equal false, repo[:fork]
    assert_equal false, repo[:pull_requests_enabled]
    assert_equal ['compression', 'archive'], repo[:topics]
  end

  should 'skip private projects' do
    stub_request(:get, "https://sourceforge.net/rest/p/privateproj/")
      .to_return(
        status: 200,
        headers: { 'Content-Type' => 'application/json' },
        body: { 'shortname' => 'privateproj', 'private' => true }.to_json
      )

    assert_nil @sourceforge.fetch_repository('privateproj')
  end

  should 'build project urls' do
    repository = build(:repository, host: @host, full_name: 'sevenzip')

    assert_equal 'https://sourceforge.net/projects/sevenzip', @sourceforge.url(repository)
    assert_equal 'https://sourceforge.net/projects/sevenzip/files/latest/download', @sourceforge.download_url(repository)
    assert_equal 'https://sourceforge.net/p/sevenzip/tickets/', @sourceforge.issues_url(repository)
  end
end
