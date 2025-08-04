FactoryBot.define do
  factory :tag do
    repository
    sequence(:name) { |n| "v#{rand(1..9)}.#{rand(0..9)}.#{n}" }
    sequence(:sha) { |n| "abc123def456#{n.to_s.rjust(3, '0')}" }
    published_at { rand(1..30).days.ago }

    trait :semantic do
      sequence(:name) { |n| "v1.#{n}.0" }
    end

    trait :prerelease do
      sequence(:name) { |n| "v1.#{n}.0-alpha.1" }
    end

    trait :unpublished do
      published_at { nil }
    end
  end
end