FactoryBot.define do
  factory :release do
    repository
    uuid { SecureRandom.uuid }
    tag_name { "v#{rand(1..9)}.#{rand(0..9)}.#{rand(0..9)}" }
    name { tag_name }
    body { "Release notes for #{tag_name}" }
    target_commitish { 'main' }
    draft { false }
    prerelease { false }
    published_at { rand(1..30).days.ago }
    author { 'octocat' }
    assets { [] }

    trait :draft do
      draft { true }
      published_at { nil }
    end

    trait :prerelease do
      prerelease { true }
    end

    trait :with_assets do
      assets do
        [
          {
            name: 'release.zip',
            download_count: rand(100..1000),
            browser_download_url: 'https://github.com/user/repo/releases/download/v1.0.0/release.zip'
          }
        ]
      end
    end

    trait :recent do
      published_at { rand(1..7).days.ago }
    end

    trait :old do
      published_at { rand(6.months..2.years).ago }
    end
  end
end