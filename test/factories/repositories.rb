FactoryBot.define do
  factory :repository do
    association :host
    sequence(:full_name) { |n| "user#{n}/repo#{n}" }
    sequence(:owner) { |n| "user#{n}" }
    fork { false }
    archived { false }
    created_at { 1.week.ago }
    updated_at { 1.day.ago }

    factory :github_repository do
      association :host, factory: :github_host
      full_name { 'testuser/awesome-project' }
      owner { 'testuser' }
    end

    factory :github_org_repository do
      association :host, factory: :github_host
      full_name { 'testorg/enterprise-app' }
      owner { 'testorg' }
    end

    factory :hidden_repository do
      association :host, factory: :github_host
      full_name { 'hiddenuser/secret-project' }
      owner { 'hiddenuser' }
    end

    factory :gitlab_repository do
      association :host, factory: :gitlab_host
      full_name { 'gitlabuser/gitlab-project' }
      owner { 'gitlabuser' }
    end

    factory :gitea_repository do
      association :host, factory: :gitea_host
      full_name { 'giteauser/gitea-project' }
      owner { 'giteauser' }
    end

    factory :bitbucket_repository do
      association :host, factory: :bitbucket_host
      full_name { 'bbuser/bitbucket-project' }
      owner { 'bbuser' }
    end

    factory :forgejo_repository do
      association :host, factory: :forgejo_host
      full_name { 'forgejouser/forgejo-project' }
      owner { 'forgejouser' }
    end

    factory :sourcehut_repository do
      association :host, factory: :sourcehut_host
      full_name { 'srhtuser/sourcehut-project' }
      owner { 'srhtuser' }
    end
  end
end