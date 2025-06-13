FactoryBot.define do
  factory :owner do
    association :host
    sequence(:login) { |n| "user#{n}" }
    sequence(:name) { |n| "User #{n}" }
    kind { 'user' }
    hidden { false }
    created_at { 1.week.ago }
    updated_at { 1.day.ago }

    factory :github_owner do
      association :host, factory: :github_host
      login { 'testuser' }
      name { 'Test User' }
    end

    factory :github_org do
      association :host, factory: :github_host
      login { 'testorg' }
      name { 'Test Organization' }
      kind { 'organization' }
    end

    factory :hidden_owner do
      association :host, factory: :github_host
      login { 'hiddenuser' }
      name { 'Hidden User' }
      hidden { true }
    end

    factory :gitlab_owner do
      association :host, factory: :gitlab_host
      login { 'gitlabuser' }
      name { 'GitLab User' }
    end

    factory :gitea_owner do
      association :host, factory: :gitea_host
      login { 'giteauser' }
      name { 'Gitea User' }
    end

    factory :bitbucket_owner do
      association :host, factory: :bitbucket_host
      login { 'bbuser' }
      name { 'Bitbucket User' }
    end

    factory :forgejo_owner do
      association :host, factory: :forgejo_host
      login { 'forgejouser' }
      name { 'Forgejo User' }
    end

    factory :sourcehut_owner do
      association :host, factory: :sourcehut_host
      login { 'srhtuser' }
      name { 'SourceHut User' }
    end
  end
end