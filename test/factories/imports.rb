FactoryBot.define do
  factory :import do
    sequence(:filename) { |n| "#{Date.current.strftime('%Y-%m-%d')}-#{n}.json.gz" }
    imported_at { Time.current }
    success { true }
    repositories_synced_count { rand(1000..5000) }
    releases_synced_count { rand(10..100) }
    error_message { nil }

    trait :failed do
      success { false }
      error_message { "Failed to download file from https://data.gharchive.org/#{filename}" }
      repositories_synced_count { 0 }
      releases_synced_count { 0 }
    end

    trait :recent do
      imported_at { rand(1..23).hours.ago }
    end

    trait :old do
      imported_at { rand(2..30).days.ago }
    end

    trait :with_high_counts do
      repositories_synced_count { rand(10000..50000) }
      releases_synced_count { rand(500..2000) }
    end
  end
end