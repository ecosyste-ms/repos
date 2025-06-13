FactoryBot.define do
  factory :host do
    sequence(:name) { |n| "Host #{n}" }
    sequence(:url) { |n| "https://example#{n}.com" }
    kind { 'github' }
    repositories_count { 0 }
    owners_count { 0 }
    created_at { 1.week.ago }
    updated_at { 1.day.ago }

    factory :github_host do
      name { 'GitHub' }
      url { 'https://github.com' }
      kind { 'github' }
    end

    factory :gitlab_host do
      name { 'GitLab' }
      url { 'https://gitlab.com' }
      kind { 'gitlab' }
    end

    factory :gitea_host do
      name { 'Gitea' }
      url { 'https://gitea.com' }
      kind { 'gitea' }
    end

    factory :bitbucket_host do
      name { 'Bitbucket' }
      url { 'https://bitbucket.org' }
      kind { 'bitbucket' }
    end

    factory :forgejo_host do
      name { 'Codeberg' }
      url { 'https://codeberg.org' }
      kind { 'forgejo' }
    end

    factory :sourcehut_host do
      name { 'SourceHut' }
      url { 'https://sr.ht' }
      kind { 'sourcehut' }
    end
  end
end