FactoryBot.define do
  factory :manifest do
    repository
    filepath { 'package.json' }
    kind { 'manifest' }

    trait :npm do
      filepath { 'package.json' }
      kind { 'manifest' }
    end

    trait :python do
      filepath { 'requirements.txt' }
      kind { 'manifest' }
    end

    trait :ruby do
      filepath { 'Gemfile' }
      kind { 'manifest' }
    end

    trait :maven do
      filepath { 'pom.xml' }
      kind { 'manifest' }
    end

    trait :gradle do
      filepath { 'build.gradle' }
      kind { 'manifest' }
    end

    trait :nuget do
      filepath { 'packages.config' }
      kind { 'manifest' }
    end

    trait :lockfile do
      kind { 'lockfile' }
    end

    trait :npm_lockfile do
      filepath { 'package-lock.json' }
      kind { 'lockfile' }
    end

    trait :yarn_lockfile do
      filepath { 'yarn.lock' }
      kind { 'lockfile' }
    end

    trait :pipfile_lock do
      filepath { 'Pipfile.lock' }
      kind { 'lockfile' }
    end

    trait :gemfile_lock do
      filepath { 'Gemfile.lock' }
      kind { 'lockfile' }
    end
  end
end