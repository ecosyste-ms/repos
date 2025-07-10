FactoryBot.define do
  factory :package_usage do
    ecosystem { 'npm' }
    name { 'lodash' }
    dependents_count { rand(1000..100000) }
    package { {} }

    trait :npm do
      ecosystem { 'npm' }
      name { %w[lodash react vue angular express].sample }
    end

    trait :pypi do
      ecosystem { 'pypi' }
      name { %w[requests django flask numpy pandas].sample }
    end

    trait :rubygems do
      ecosystem { 'rubygems' }
      name { %w[rails activerecord activesupport].sample }
    end

    trait :maven do
      ecosystem { 'maven' }
      name { 'org.springframework:spring-core' }
    end

    trait :nuget do
      ecosystem { 'nuget' }
      name { %w[Newtonsoft.Json EntityFramework].sample }
    end

    trait :popular do
      dependents_count { rand(50000..500000) }
    end

    trait :unpopular do
      dependents_count { rand(1..100) }
    end
  end
end