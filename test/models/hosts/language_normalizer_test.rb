require "test_helper"

class Hosts::LanguageNormalizerTest < ActiveSupport::TestCase
  context 'normalize' do
    should 'map lowercase names to the Linguist spelling' do
      assert_equal 'Java', Hosts::LanguageNormalizer.normalize('java')
      assert_equal 'JavaScript', Hosts::LanguageNormalizer.normalize('javascript')
      assert_equal 'C++', Hosts::LanguageNormalizer.normalize('c++')
      assert_equal 'C#', Hosts::LanguageNormalizer.normalize('c#')
      assert_equal 'Objective-C', Hosts::LanguageNormalizer.normalize('objective-c')
    end

    should 'leave canonical names unchanged' do
      assert_equal 'Ruby', Hosts::LanguageNormalizer.normalize('Ruby')
    end

    should 'ignore surrounding whitespace' do
      assert_equal 'Python', Hosts::LanguageNormalizer.normalize(' python ')
    end

    should 'return unknown names unchanged' do
      assert_equal 'Not A Real Language', Hosts::LanguageNormalizer.normalize('Not A Real Language')
    end

    should 'return nil for nil and blank values' do
      assert_nil Hosts::LanguageNormalizer.normalize(nil)
      assert_nil Hosts::LanguageNormalizer.normalize('')
    end
  end

  context 'host adapters' do
    should 'normalize the language in Gitea repository data' do
      host = create(:host, url: 'https://gitea.example.com', kind: 'gitea')
      adapter = Hosts::Gitea.new(host)
      adapter.stubs(:fetch_topics).returns([])

      data = adapter.map_repository_data('id' => 1, 'full_name' => 'octo/app', 'language' => 'java')

      assert_equal 'Java', data[:language]
    end

    should 'normalize the language in Forgejo repository data' do
      host = create(:host, url: 'https://forgejo.example.com', kind: 'forgejo')
      adapter = Hosts::Forgejo.new(host)
      adapter.stubs(:fetch_topics).returns([])

      data = adapter.map_repository_data('id' => 1, 'full_name' => 'octo/app', 'language' => 'ruby')

      assert_equal 'Ruby', data[:language]
    end

    should 'normalize the language in Bitbucket repository data' do
      host = create(:host, url: 'https://bitbucket.org', kind: 'bitbucket')
      adapter = Hosts::Bitbucket.new(host)
      stub_request(:get, 'https://api.bitbucket.org/2.0/repositories/octo/app')
        .to_return(status: 200, headers: { 'Content-Type' => 'application/json' },
                   body: { 'uuid' => '{1}', 'full_name' => 'octo/app', 'language' => 'java', 'is_private' => false }.to_json)

      data = adapter.fetch_repository('octo/app')

      assert_equal 'Java', data[:language]
    end
  end
end
