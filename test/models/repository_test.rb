require "test_helper"

class RepositoryTest < ActiveSupport::TestCase
  context 'associations' do
    should belong_to(:host)
    should have_many(:manifests)
    should have_many(:tags)
    should have_many(:releases)
    should have_one(:scorecard)

    should 'delete_all tags when repository is destroyed' do
      repository = create(:repository)
      tag1 = create(:tag, repository: repository)
      tag2 = create(:tag, repository: repository)
      
      assert_equal 2, repository.tags.count
      
      repository.destroy
      
      assert_equal 0, Tag.where(id: [tag1.id, tag2.id]).count
    end

    should 'delete_all releases when repository is destroyed' do
      repository = create(:repository)
      release1 = create(:release, repository: repository)
      release2 = create(:release, repository: repository)
      
      assert_equal 2, repository.releases.count
      
      repository.destroy
      
      assert_equal 0, Release.where(id: [release1.id, release2.id]).count
    end
  end

  context 'purl method' do
    setup do
      @host = Host.create!(name: 'GitHub', url: 'https://github.com', kind: 'github')
      @repository = Repository.create!(
        full_name: 'rails/rails',
        owner: 'rails',
        uuid: '123',
        host: @host,
        created_at: Time.now,
        updated_at: Time.now
      )
    end

    should 'generate correct purl for github repository' do
      expected_purl = "pkg:github/rails/rails"
      assert_equal expected_purl, @repository.purl
    end
  end

  context 'scorecard' do
    should 'return true for has_scorecard? when scorecard exists' do
      repository = create(:repository)
      create(:scorecard, repository: repository)
      assert repository.has_scorecard?
    end

    should 'return false for has_scorecard? when no scorecard exists' do
      repository = create(:repository)
      assert_not repository.has_scorecard?
    end
  end

  context 'owner_hidden? method' do
    setup do
      @host = Host.create!(name: 'GitHub', url: 'https://github.com', kind: 'github')
      @visible_owner = Owner.create!(login: 'visible', host: @host, hidden: false)
      @hidden_owner = Owner.create!(login: 'hidden', host: @host, hidden: true)
      @nil_owner = Owner.create!(login: 'nil-owner', host: @host, hidden: nil)
    end

    should 'return false for repository with visible owner' do
      repository = Repository.create!(
        full_name: 'visible/repo',
        owner: 'visible',
        uuid: '123',
        host: @host,
        created_at: Time.now,
        updated_at: Time.now
      )
      assert_equal false, repository.owner_hidden?
    end

    should 'return true for repository with hidden owner' do
      repository = Repository.create!(
        full_name: 'hidden/repo',
        owner: 'hidden',
        uuid: '123',
        host: @host,
        created_at: Time.now,
        updated_at: Time.now
      )
      assert_equal true, repository.owner_hidden?
    end

    should 'return false for repository with nil hidden owner' do
      repository = Repository.create!(
        full_name: 'nil-owner/repo',
        owner: 'nil-owner',
        uuid: '123',
        host: @host,
        created_at: Time.now,
        updated_at: Time.now
      )
      assert_equal false, repository.owner_hidden?
    end

    should 'return false for repository with no owner' do
      repository = Repository.create!(
        full_name: 'no/owner',
        owner: '',
        uuid: '123',
        host: @host,
        created_at: Time.now,
        updated_at: Time.now
      )
      assert_equal false, repository.owner_hidden?
    end

    should 'return false for repository with nonexistent owner' do
      repository = Repository.create!(
        full_name: 'nonexistent/repo',
        owner: 'nonexistent',
        uuid: '123',
        host: @host,
        created_at: Time.now,
        updated_at: Time.now
      )
      assert_equal false, repository.owner_hidden?
    end
  end

  context 'sync method' do
    should 'return early if host is nil' do
      repository = Repository.new(
        full_name: 'test/repo',
        owner: 'test',
        uuid: '456',
        host: nil,
        created_at: Time.now,
        updated_at: Time.now
      )
      
      assert_nil repository.sync
    end
  end

  context 'sync_scorecard method' do
    should 'call Scorecard.lookup with self' do
      host = create(:host)
      repository = create(:repository, host: host)
      
      stub_request(:get, "https://api.scorecard.dev/projects/#{repository.html_url.gsub(%r{http(s)?://}, '')}")
        .to_return(status: 200, body: { score: 8.0, repo: { name: repository.full_name } }.to_json)
      
      scorecard = repository.sync_scorecard
      
      assert_not_nil scorecard
      assert_equal repository, scorecard.repository
      assert_equal 8.0, scorecard.score
    end
  end

  context 'sync_scorecard_async method' do
    should 'call SyncScorecardWorker.perform_async' do
      host = create(:host)
      repository = create(:repository, host: host)
      
      SyncScorecardWorker.expects(:perform_async).with(repository.id).once
      
      repository.sync_scorecard_async
    end
  end

  context 'has_scorecard scope' do
    should 'return repositories with scorecards' do
      host = create(:host)
      repo_with_scorecard = create(:repository, host: host)
      repo_without_scorecard = create(:repository, host: host)
      create(:scorecard, repository: repo_with_scorecard)
      
      repositories_with_scorecards = Repository.has_scorecard
      
      assert_includes repositories_with_scorecards, repo_with_scorecard
      assert_not_includes repositories_with_scorecards, repo_without_scorecard
    end
  end

  context 'fetch_metadata_files_list method' do
    setup do
      @host = create(:host)
      @repository = create(:repository, host: @host)
    end

    should 'return nil when file list is blank' do
      @repository.stubs(:get_file_list).returns(nil)
      assert_nil @repository.fetch_metadata_files_list
      
      @repository.stubs(:get_file_list).returns([])
      assert_nil @repository.fetch_metadata_files_list
    end

    should 'find readme files in various locations' do
      file_list = [
        'README.md',
        'docs/README.txt',
        '.github/README.rst',
        '.gitlab/README',
        'readme.markdown',
        'other.txt'
      ]
      @repository.stubs(:get_file_list).returns(file_list)
      
      result = @repository.fetch_metadata_files_list
      assert_equal 'README.md', result[:readme]
    end

    should 'find changelog files' do
      file_list = [
        'CHANGELOG.md',
        'HISTORY.txt',
        'NEWS.rst',
        'changes.md',
        'other.txt'
      ]
      @repository.stubs(:get_file_list).returns(file_list)
      
      result = @repository.fetch_metadata_files_list
      assert_equal 'CHANGELOG.md', result[:changelog]
    end

    should 'find contributing files in various locations' do
      file_list = [
        'CONTRIBUTING.md',
        'docs/CONTRIBUTING.txt',
        '.github/CONTRIBUTING.rst',
        '.gitlab/CONTRIBUTING',
        'contributing.markdown',
        'other.txt'
      ]
      @repository.stubs(:get_file_list).returns(file_list)
      
      result = @repository.fetch_metadata_files_list
      assert_equal 'CONTRIBUTING.md', result[:contributing]
    end

    should 'find funding files' do
      file_list = [
        'FUNDING.yml',
        '.github/FUNDING.yaml',
        'docs/FUNDING.yml',
        '.gitlab/FUNDING.yaml',
        'funding.txt',
        'other.txt'
      ]
      @repository.stubs(:get_file_list).returns(file_list)
      
      result = @repository.fetch_metadata_files_list
      assert_equal 'FUNDING.yml', result[:funding]
    end

    should 'find license files' do
      file_list = [
        'LICENSE',
        'COPYING',
        'MIT-LICENSE',
        'license.txt',
        'other.txt'
      ]
      @repository.stubs(:get_file_list).returns(file_list)
      
      result = @repository.fetch_metadata_files_list
      assert_equal 'LICENSE', result[:license]
    end

    should 'find code of conduct files' do
      file_list = [
        'CODE_OF_CONDUCT.md',
        'CODE-OF-CONDUCT.txt',
        '.github/CODE_OF_CONDUCT.rst',
        'docs/CODE-OF-CONDUCT',
        '.gitlab/CODE_OF_CONDUCT.md',
        'code_of_conduct.lowercase',
        'other.txt'
      ]
      @repository.stubs(:get_file_list).returns(file_list)
      
      result = @repository.fetch_metadata_files_list
      assert_equal 'CODE_OF_CONDUCT.md', result[:code_of_conduct]
    end

    should 'find threat model files' do
      file_list = [
        'THREAT_MODEL.md',
        'THREAT-MODEL.txt',
        'threat_model.lowercase',
        'other.txt'
      ]
      @repository.stubs(:get_file_list).returns(file_list)
      
      result = @repository.fetch_metadata_files_list
      assert_equal 'THREAT_MODEL.md', result[:threat_model]
    end

    should 'find audit files' do
      file_list = [
        'AUDIT.md',
        'audit.txt',
        'other.txt'
      ]
      @repository.stubs(:get_file_list).returns(file_list)
      
      result = @repository.fetch_metadata_files_list
      assert_equal 'AUDIT.md', result[:audit]
    end

    should 'find citation files' do
      file_list = [
        'CITATION.cff',
        'citation.md',
        'other.txt'
      ]
      @repository.stubs(:get_file_list).returns(file_list)
      
      result = @repository.fetch_metadata_files_list
      assert_equal 'CITATION.cff', result[:citation]
    end

    should 'find codeowners files in various locations' do
      file_list = [
        'CODEOWNERS',
        '.github/CODEOWNERS',
        'docs/CODEOWNERS',
        '.gitlab/CODEOWNERS',
        'codeowners.txt',
        'other.txt'
      ]
      @repository.stubs(:get_file_list).returns(file_list)
      
      result = @repository.fetch_metadata_files_list
      assert_equal 'CODEOWNERS', result[:codeowners]
    end

    should 'find security files in various locations' do
      file_list = [
        'SECURITY.md',
        '.github/SECURITY.txt',
        'docs/SECURITY.rst',
        '.gitlab/SECURITY',
        'security.lowercase',
        'other.txt'
      ]
      @repository.stubs(:get_file_list).returns(file_list)
      
      result = @repository.fetch_metadata_files_list
      assert_equal 'SECURITY.md', result[:security]
    end

    should 'find support files in various locations' do
      file_list = [
        'SUPPORT.md',
        '.github/SUPPORT.txt',
        'docs/SUPPORT.rst',
        '.gitlab/SUPPORT',
        'support.lowercase',
        'other.txt'
      ]
      @repository.stubs(:get_file_list).returns(file_list)
      
      result = @repository.fetch_metadata_files_list
      assert_equal 'SUPPORT.md', result[:support]
    end

    should 'find governance files in various locations' do
      file_list = [
        'GOVERNANCE.md',
        '.github/GOVERNANCE.txt',
        'docs/GOVERNANCE.rst',
        '.gitlab/GOVERNANCE',
        'governance.lowercase',
        'other.txt'
      ]
      @repository.stubs(:get_file_list).returns(file_list)
      
      result = @repository.fetch_metadata_files_list
      assert_equal 'GOVERNANCE.md', result[:governance]
    end

    should 'find roadmap files in various locations' do
      file_list = [
        'ROADMAP.md',
        '.github/ROADMAP.txt',
        'docs/ROADMAP.rst',
        '.gitlab/ROADMAP',
        'roadmap.lowercase',
        'other.txt'
      ]
      @repository.stubs(:get_file_list).returns(file_list)
      
      result = @repository.fetch_metadata_files_list
      assert_equal 'ROADMAP.md', result[:roadmap]
    end

    should 'find authors files' do
      file_list = [
        'AUTHORS',
        'AUTHORS.md',
        'authors.txt',
        'other.txt'
      ]
      @repository.stubs(:get_file_list).returns(file_list)
      
      result = @repository.fetch_metadata_files_list
      assert_equal 'AUTHORS', result[:authors]
    end

    should 'find dei files in various locations' do
      file_list = [
        'DEI.md',
        '.github/DEI.txt',
        'docs/DEI.rst',
        '.gitlab/DEI',
        'dei.lowercase',
        'other.txt'
      ]
      @repository.stubs(:get_file_list).returns(file_list)
      
      result = @repository.fetch_metadata_files_list
      assert_equal 'DEI.md', result[:dei]
    end

    should 'find publiccode files' do
      file_list = [
        'publiccode.yml',
        'publiccode.yaml',
        'publiccode.txt',
        'other.txt'
      ]
      @repository.stubs(:get_file_list).returns(file_list)
      
      result = @repository.fetch_metadata_files_list
      assert_equal 'publiccode.yml', result[:publiccode]
    end

    should 'find codemeta files' do
      file_list = [
        'codemeta.json',
        'codemeta.txt',
        'other.txt'
      ]
      @repository.stubs(:get_file_list).returns(file_list)
      
      result = @repository.fetch_metadata_files_list
      assert_equal 'codemeta.json', result[:codemeta]
    end

    should 'find zenodo files' do
      file_list = [
        '.zenodo.json',
        'zenodo.json',
        'other.txt'
      ]
      @repository.stubs(:get_file_list).returns(file_list)
      
      result = @repository.fetch_metadata_files_list
      assert_equal '.zenodo.json', result[:zenodo]
    end

    should 'find notice files with various extensions' do
      file_list = [
        'NOTICE',
        'NOTICE.md',
        'NOTICE.txt',
        '.github/NOTICE',
        'docs/NOTICE.md',
        '.gitlab/NOTICE.txt',
        'notice.lowercase',
        'other.txt'
      ]
      @repository.stubs(:get_file_list).returns(file_list)
      
      result = @repository.fetch_metadata_files_list
      assert_equal 'NOTICE', result[:notice]
    end

    should 'find maintainers files with various extensions' do
      file_list = [
        'MAINTAINERS',
        'MAINTAINERS.md',
        'MAINTAINERS.txt',
        '.github/MAINTAINERS',
        'docs/MAINTAINERS.md',
        '.gitlab/MAINTAINERS.txt',
        'maintainers.lowercase',
        'other.txt'
      ]
      @repository.stubs(:get_file_list).returns(file_list)
      
      result = @repository.fetch_metadata_files_list
      assert_equal 'MAINTAINERS', result[:maintainers]
    end

    should 'find copyright files with various extensions' do
      file_list = [
        'COPYRIGHT',
        'COPYRIGHT.md',
        'COPYRIGHT.txt',
        'copyright.lowercase',
        'other.txt'
      ]
      @repository.stubs(:get_file_list).returns(file_list)
      
      result = @repository.fetch_metadata_files_list
      assert_equal 'COPYRIGHT', result[:copyright]
    end

    should 'find agents files' do
      file_list = [
        'AGENTS.md',
        '.github/AGENTS.md',
        'docs/AGENTS.md',
        '.gitlab/AGENTS.md',
        'agents.txt',
        'other.txt'
      ]
      @repository.stubs(:get_file_list).returns(file_list)
      
      result = @repository.fetch_metadata_files_list
      assert_equal 'AGENTS.md', result[:agents]
    end

    should 'find dco files with various extensions' do
      file_list = [
        'DCO',
        'DCO.md',
        'DCO.txt',
        '.github/DCO',
        'docs/DCO.md',
        '.gitlab/DCO.txt',
        'dco.lowercase',
        'other.txt'
      ]
      @repository.stubs(:get_file_list).returns(file_list)
      
      result = @repository.fetch_metadata_files_list
      assert_equal 'DCO', result[:dco]
    end

    should 'find cla files with various names and extensions' do
      file_list = [
        'CLA',
        'CLA.md',
        'CLA.txt',
        'CONTRIBUTOR_LICENSE_AGREEMENT',
        'CONTRIBUTOR-LICENSE-AGREEMENT.md',
        'CONTRIBUTOR LICENSE AGREEMENT.txt',
        '.github/CLA.md',
        'docs/CONTRIBUTOR_LICENSE_AGREEMENT',
        '.gitlab/CONTRIBUTOR-LICENSE-AGREEMENT.txt',
        'cla.lowercase',
        'other.txt'
      ]
      @repository.stubs(:get_file_list).returns(file_list)
      
      result = @repository.fetch_metadata_files_list
      assert_equal 'CLA', result[:cla]
    end

    should 'return hash with all keys even when no files match' do
      file_list = ['unrelated.txt', 'random.file']
      @repository.stubs(:get_file_list).returns(file_list)
      
      result = @repository.fetch_metadata_files_list
      
      assert_instance_of Hash, result
      assert_nil result[:readme]
      assert_nil result[:changelog]
      assert_nil result[:contributing]
      assert_nil result[:funding]
      assert_nil result[:license]
      assert_nil result[:code_of_conduct]
      assert_nil result[:threat_model]
      assert_nil result[:audit]
      assert_nil result[:citation]
      assert_nil result[:codeowners]
      assert_nil result[:security]
      assert_nil result[:support]
      assert_nil result[:governance]
      assert_nil result[:roadmap]
      assert_nil result[:authors]
      assert_nil result[:dei]
      assert_nil result[:publiccode]
      assert_nil result[:codemeta]
      assert_nil result[:zenodo]
      assert_nil result[:notice]
      assert_nil result[:maintainers]
      assert_nil result[:copyright]
      assert_nil result[:agents]
      assert_nil result[:dco]
      assert_nil result[:cla]
    end

    should 'handle mixed case and find first matching file' do
      file_list = [
        'readme.md',
        'README.MD',
        'ReadMe.txt',
        'LICENSE.txt',
        'License',
        'LICENCE'
      ]
      @repository.stubs(:get_file_list).returns(file_list)
      
      result = @repository.fetch_metadata_files_list
      assert_equal 'readme.md', result[:readme]
      assert_equal 'LICENSE.txt', result[:license]
    end
  end

  context 'has_blocked_topic? method' do
    setup do
      @host = Host.create!(name: 'GitHub', url: 'https://github.com', kind: 'github')
    end

    should 'return false when topics are blank' do
      repository = Repository.create!(
        full_name: 'test/repo',
        owner: 'test',
        uuid: '123',
        host: @host,
        topics: nil,
        created_at: Time.now,
        updated_at: Time.now
      )
      ENV['BLOCKED_TOPICS'] = 'bad-topic'
      assert_equal false, repository.has_blocked_topic?
      ENV.delete('BLOCKED_TOPICS')
    end

    should 'return false when BLOCKED_TOPICS env var is not set' do
      repository = Repository.create!(
        full_name: 'test/repo',
        owner: 'test',
        uuid: '123',
        host: @host,
        topics: ['good-topic'],
        created_at: Time.now,
        updated_at: Time.now
      )
      ENV.delete('BLOCKED_TOPICS')
      assert_equal false, repository.has_blocked_topic?
    end

    should 'return true when repository has a blocked topic' do
      repository = Repository.create!(
        full_name: 'test/repo',
        owner: 'test',
        uuid: '123',
        host: @host,
        topics: ['good-topic', 'malwarebytes-unlocked-version', 'another-topic'],
        created_at: Time.now,
        updated_at: Time.now
      )
      ENV['BLOCKED_TOPICS'] = 'malwarebytes-unlocked-version,premiere-crack-2023'
      assert_equal true, repository.has_blocked_topic?
      ENV.delete('BLOCKED_TOPICS')
    end

    should 'return false when repository has no blocked topics' do
      repository = Repository.create!(
        full_name: 'test/repo',
        owner: 'test',
        uuid: '123',
        host: @host,
        topics: ['good-topic', 'another-good-topic'],
        created_at: Time.now,
        updated_at: Time.now
      )
      ENV['BLOCKED_TOPICS'] = 'malwarebytes-unlocked-version,premiere-crack-2023'
      assert_equal false, repository.has_blocked_topic?
      ENV.delete('BLOCKED_TOPICS')
    end

    should 'handle comma separated list with spaces' do
      repository = Repository.create!(
        full_name: 'test/repo',
        owner: 'test',
        uuid: '123',
        host: @host,
        topics: ['download-free-dxo-photolab'],
        created_at: Time.now,
        updated_at: Time.now
      )
      ENV['BLOCKED_TOPICS'] = 'malwarebytes-unlocked-version, download-free-dxo-photolab , premiere-crack-2023'
      assert_equal true, repository.has_blocked_topic?
      ENV.delete('BLOCKED_TOPICS')
    end
  end

  context 'sync methods with hidden owners' do
    setup do
      @host = FactoryBot.create(:github_host)
      @visible_owner = FactoryBot.create(:owner, host: @host, login: 'visible', hidden: false)
      @hidden_owner = FactoryBot.create(:hidden_owner, host: @host, login: 'hidden')
      @visible_repo = FactoryBot.create(:repository, host: @host, full_name: 'visible/repo', owner: 'visible')
      @hidden_repo = FactoryBot.create(:repository, host: @host, full_name: 'hidden/repo', owner: 'hidden')
    end

    should 'not sync repository with hidden owner' do
      @host.expects(:host_instance).never
      @hidden_repo.sync
    end

    should 'sync repository with visible owner' do
      @host.stubs(:host_instance).returns(mock('host_instance').tap do |m|
        m.expects(:update_from_host).with(@visible_repo).once
      end)
      @visible_repo.sync
    end

    should 'not sync_owner for repository with hidden owner' do
      @host.expects(:sync_owner).never
      @hidden_repo.sync_owner
    end

    should 'not sync_owner_async for repository with hidden owner' do
      @host.expects(:sync_owner_async).never
      @hidden_repo.sync_owner_async
    end

    should 'not sync_extra_details for repository with hidden owner' do
      @hidden_repo.expects(:parse_dependencies).never
      @hidden_repo.expects(:update_metadata_files).never
      @hidden_repo.sync_extra_details(force: true)
    end

    should 'sync_extra_details for repository with visible owner' do
      @visible_repo.update(files_changed: true, pushed_at: 1.day.ago)
      @visible_repo.expects(:parse_dependencies).at_least_once
      @visible_repo.expects(:update_metadata_files).once
      @visible_repo.expects(:download_tags).once
      @visible_repo.sync_extra_details
    end
  end
end
