require "test_helper"

class Hosts::GitlabTest < ActiveSupport::TestCase
  context 'recently_changed_repo_names' do
    setup do
      @host = create(:host, url: 'https://gitlab.com', kind: 'gitlab')
      @gitlab_instance = Hosts::Gitlab.new(@host)
    end

    should 'handle empty array from load_repo_names' do
      @gitlab_instance.stubs(:load_repo_names).returns([])
      
      result = @gitlab_instance.recently_changed_repo_names
      
      assert_equal [], result
    end

    should 'handle nil entries in repos array' do
      repos_with_nil = [
        { "path_with_namespace" => "user/repo1", "last_activity_at" => 2.hours.ago },
        nil
      ]
      @gitlab_instance.stubs(:load_repo_names).returns(repos_with_nil)
      
      result = @gitlab_instance.recently_changed_repo_names
      
      assert_equal [], result
    end

    should 'return repo names and stop pagination when oldest is older than target' do
      recent_time = 30.minutes.ago
      old_time = 2.hours.ago
      
      first_page = [
        { "path_with_namespace" => "user/repo1", "last_activity_at" => recent_time },
        { "path_with_namespace" => "user/repo2", "last_activity_at" => recent_time }
      ]
      
      second_page = [
        { "path_with_namespace" => "user/repo3", "last_activity_at" => old_time }
      ]
      
      @gitlab_instance.stubs(:load_repo_names).with(1, "updated_at").returns(first_page)
      @gitlab_instance.stubs(:load_repo_names).with(2, "updated_at").returns(second_page)
      
      result = @gitlab_instance.recently_changed_repo_names(1.hour)
      
      assert_equal ["user/repo1", "user/repo2", "user/repo3"], result
    end

    should 'handle pagination correctly and stop on empty page' do
      recent_time = 30.minutes.ago
      older_time = 45.minutes.ago
      old_time = 2.hours.ago
      
      page1 = [
        { "path_with_namespace" => "user/repo1", "last_activity_at" => recent_time },
        { "path_with_namespace" => "user/repo2", "last_activity_at" => older_time }
      ]
      
      page2 = [
        { "path_with_namespace" => "user/repo3", "last_activity_at" => older_time },
        { "path_with_namespace" => "user/repo4", "last_activity_at" => old_time }
      ]
      
      @gitlab_instance.stubs(:load_repo_names).with(1, "updated_at").returns(page1)
      @gitlab_instance.stubs(:load_repo_names).with(2, "updated_at").returns(page2)
      
      result = @gitlab_instance.recently_changed_repo_names(1.hour)
      
      assert_equal ["user/repo1", "user/repo2", "user/repo3", "user/repo4"], result
    end

    should 'remove duplicate repo names' do
      recent_time = 30.minutes.ago
      old_time = 2.hours.ago
      
      page1 = [
        { "path_with_namespace" => "user/repo1", "last_activity_at" => recent_time },
        { "path_with_namespace" => "user/repo1", "last_activity_at" => recent_time }
      ]
      
      page2 = [
        { "path_with_namespace" => "user/repo1", "last_activity_at" => old_time }
      ]
      
      @gitlab_instance.stubs(:load_repo_names).with(1, "updated_at").returns(page1)
      @gitlab_instance.stubs(:load_repo_names).with(2, "updated_at").returns(page2)
      
      result = @gitlab_instance.recently_changed_repo_names
      
      assert_equal ["user/repo1"], result
    end
  end
end
class Hosts::GitlabLanguageTest < ActiveSupport::TestCase
  context 'fetch_repository languages' do
    setup do
      @host = create(:host, url: 'https://gitlab.com', kind: 'gitlab')
      @gitlab_instance = Hosts::Gitlab.new(@host)
      @project = OpenStruct.new(
        id: 123,
        description: 'AMIRIS energy market model',
        created_at: Time.zone.parse('2024-01-01'),
        name: 'amiris',
        open_issues_count: 4,
        forks_count: 2,
        default_branch: 'main',
        archived: false,
        topics: ['energy'],
        namespace: OpenStruct.new(kind: 'group'),
        visibility: 'public',
        path_with_namespace: 'dlr-ve/esy/amiris/amiris',
        last_activity_at: Time.zone.parse('2024-02-01'),
        star_count: 12,
        issues_enabled: true,
        wiki_enabled: false,
        vcs_type: 'git',
        merge_requests_enabled: true,
        avatar_url: 'https://gitlab.com/uploads/project/avatar.png',
        forked_from_project: nil,
        license: OpenStruct.new(key: 'apache-2.0')
      )
      @api_client = mock('gitlab_api_client')
      @gitlab_instance.stubs(:api_client).returns(@api_client)
    end

    should 'populate language and language metadata from GitLab languages endpoint' do
      @api_client.expects(:project).with('dlr-ve/esy/amiris/amiris', license: true).returns(@project)
      @api_client.expects(:project_languages).with('dlr-ve/esy/amiris/amiris').returns({ 'Java' => 98.15, 'Python' => 1.14, 'BibTeX' => 0.71 })

      repository = @gitlab_instance.fetch_repository('dlr-ve/esy/amiris/amiris')

      assert_equal 'Java', repository[:language]
      assert_equal({ 'Java' => 98.15, 'Python' => 1.14, 'BibTeX' => 0.71 }, repository[:metadata][:languages])
    end

    should 'keep language nil when GitLab languages endpoint is unavailable' do
      @api_client.expects(:project).with('dlr-ve/esy/amiris/amiris-py', license: true).returns(@project)
      @api_client.expects(:project_languages).with('dlr-ve/esy/amiris/amiris').raises(::Gitlab::Error::NotFound)

      repository = @gitlab_instance.fetch_repository('dlr-ve/esy/amiris/amiris-py')

      assert_nil repository[:language]
      assert_equal({}, repository[:metadata])
    end
  end
end
