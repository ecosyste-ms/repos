require "test_helper"

class CgitTest < ActiveSupport::TestCase
  setup do
    @host = Host.new(name: 'cgit', url: 'https://git.zx2c4.com', kind: 'cgit')
    @cgit = Hosts::Cgit.new(@host)
  end

  test 'maps cgit repository page metadata' do
    html = <<~HTML
      <!DOCTYPE html>
      <html>
        <head>
          <title>wireguard-tools - Required tools for WireGuard</title>
          <meta name="generator" content="cgit v1.3" />
          <link rel="alternate" title="Atom feed" href="https://git.zx2c4.com/wireguard-tools/atom/?h=master" type="application/atom+xml" />
        </head>
      </html>
    HTML

    mapped = @cgit.map_repository_data('wireguard-tools', html)

    assert_equal 'wireguard-tools', mapped[:uuid]
    assert_equal 'wireguard-tools', mapped[:full_name]
    assert_equal 'Required tools for WireGuard', mapped[:description]
    assert_equal 'master', mapped[:default_branch]
    assert_equal 'git', mapped[:scm]
    assert_equal false, mapped[:has_issues]
    assert_equal [], mapped[:topics]
    assert_equal 'wireguard-tools', mapped[:metadata][:cgit_name]
    assert_equal 'cgit v1.3', mapped[:metadata][:generator]
  end

  test 'builds cgit URLs' do
    repository = Repository.new(host: @host, full_name: 'wireguard-tools', default_branch: 'master')

    assert_equal 'https://git.zx2c4.com/wireguard-tools', @cgit.url(repository)
    assert_equal 'https://git.zx2c4.com/wireguard-tools/plain/?h=master', @cgit.raw_url(repository)
    assert_equal 'https://git.zx2c4.com/wireguard-tools/snapshot/wireguard-tools-master.tar.gz', @cgit.download_url(repository)
  end
end
