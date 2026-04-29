require 'test_helper'

class SourcehutTest < ActiveSupport::TestCase
  setup do
    @host = build(:sourcehut_host, url: 'https://sr.ht')
    @sourcehut = Hosts::Sourcehut.new(@host)
    @repository = build(:sourcehut_repository, host: @host, full_name: 'sircmpwn/git.sr.ht', default_branch: 'master')
  end

  test 'formats sourcehut repository urls on git host' do
    assert_equal 'https://git.sr.ht/~sircmpwn/git.sr.ht', @sourcehut.url(@repository)
    assert_equal 'https://git.sr.ht/~sircmpwn/git.sr.ht/tree/master/', @sourcehut.blob_url(@repository)
    assert_equal 'https://git.sr.ht/~sircmpwn/git.sr.ht/blob/master/', @sourcehut.raw_url(@repository)
    assert_equal 'https://git.sr.ht/~sircmpwn/git.sr.ht/archive/master.tar.gz', @sourcehut.download_url(@repository)
  end

  test 'maps sourcehut html repository metadata' do
    html = <<~HTML
      <title>
      ~sircmpwn/git.sr.ht -

      sr.ht git services -

      sourcehut git
      </title>
      <meta name="vcs" content="git">
      <meta name="vcs:default-branch" content="main">
      <div class="header-extension">
        <div class="container"><div class="row"><div class="col-md-6">
          sr.ht git services
        </div></div></div>
      </div>
      <span title="2026-04-08 09:01:21 UTC">20 days ago</span>
    HTML

    data = @sourcehut.map_repository_data('~sircmpwn/git.sr.ht', html)

    assert_equal '~sircmpwn/git.sr.ht', data[:full_name]
    assert_equal 'sircmpwn', data[:owner]
    assert_equal 'sr.ht git services', data[:description]
    assert_equal 'main', data[:default_branch]
    assert_equal 'git', data[:scm]
    assert_equal false, data[:private]
    assert_equal false, data[:has_issues]
    assert_equal Time.parse('2026-04-08 09:01:21 UTC'), data[:pushed_at]
  end
end
