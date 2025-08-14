FactoryBot.define do
  factory :scorecard do
    data { { 'repo' => { 'name' => 'test/repo' }, 'score' => 7.5 } }
    last_synced_at { 1.hour.ago }
    association :repository
  end
end