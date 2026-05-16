require "test_helper"

class GerritTest < ActiveSupport::TestCase
  setup do
    @host = Host.new(name: 'Coreboot Gerrit', url: 'https://review.coreboot.org', kind: 'gerrit')
    @gerrit = Hosts::Gerrit.new(@host)
  end

  test 'maps gerrit project data to repository attributes' do
    data = {
      'id' => 'coreboot',
      'name' => 'coreboot',
      'parent' => 'All-Projects',
      'description' => 'coreboot main repository',
      'state' => 'ACTIVE',
      'branches' => { 'HEAD' => 'main' },
      'web_links' => [{ 'name' => 'gitweb', 'url' => 'https://review.coreboot.org/plugins/gitiles/coreboot' }]
    }

    mapped = @gerrit.map_repository_data(data)

    assert_equal 'coreboot', mapped[:uuid]
    assert_equal 'coreboot', mapped[:full_name]
    assert_equal 'All-Projects', mapped[:owner]
    assert_equal 'coreboot main repository', mapped[:description]
    assert_equal 'main', mapped[:default_branch]
    assert_equal 'git', mapped[:scm]
    assert_equal false, mapped[:has_issues]
    assert_equal [], mapped[:topics]
    assert_equal 'ACTIVE', mapped[:metadata][:state]
  end

  test 'builds gerrit gitiles URLs' do
    repository = Repository.new(host: @host, full_name: 'coreboot', default_branch: 'main')

    assert_equal 'https://review.coreboot.org/plugins/gitiles/coreboot', @gerrit.url(repository)
    assert_equal 'https://review.coreboot.org/plugins/gitiles/coreboot/+/main/', @gerrit.raw_url(repository)
    assert_equal 'https://review.coreboot.org/plugins/gitiles/coreboot/+archive/main.tar.gz', @gerrit.download_url(repository)
  end
end
