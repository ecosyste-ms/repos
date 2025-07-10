FactoryBot.define do
  factory :dependency do
    repository
    manifest
    ecosystem { 'npm' }
    package_name { 'lodash' }
    requirements { '^4.17.0' }
    kind { 'runtime' }

    trait :development do
      kind { 'development' }
    end

    trait :peer do
      kind { 'peer' }
    end

    trait :optional do
      kind { 'optional' }
    end

    trait :npm do
      ecosystem { 'npm' }
      package_name { %w[lodash react vue angular].sample }
      requirements { "^#{rand(1..5)}.#{rand(0..9)}.#{rand(0..9)}" }
    end

    trait :pypi do
      ecosystem { 'pypi' }
      package_name { %w[django flask requests numpy pandas].sample }
      requirements { ">=#{rand(1..5)}.#{rand(0..9)}.#{rand(0..9)}" }
    end

    trait :rubygems do
      ecosystem { 'rubygems' }
      package_name { %w[rails sinatra activerecord].sample }
      requirements { "~> #{rand(1..7)}.#{rand(0..9)}" }
    end

    trait :maven do
      ecosystem { 'maven' }
      package_name { 'org.springframework:spring-core' }
      requirements { "#{rand(4..5)}.#{rand(0..9)}.#{rand(0..9)}" }
    end

    trait :nuget do
      ecosystem { 'nuget' }
      package_name { %w[Newtonsoft.Json EntityFramework AutoMapper].sample }
      requirements { "#{rand(8..13)}.#{rand(0..9)}.#{rand(0..9)}" }
    end
  end
end