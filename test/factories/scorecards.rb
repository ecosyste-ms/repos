FactoryBot.define do
  factory :scorecard do
    data do
      {
        'date' => '2025-08-04',
        'repo' => {
          'name' => 'github.com/test/repo',
          'commit' => '3f6ad2ae50bec8ff722d74965f888fd319882495'
        },
        'scorecard' => {
          'version' => 'v5.2.1-28-gc1d103a9',
          'commit' => 'c1d103a9bb9f635ec7260bf9aa0699466fa4be0e'
        },
        'score' => 7.5,
        'checks' => [
          {
            'name' => 'Maintained',
            'score' => 10,
            'reason' => '15 commit(s) and 1 issue activity found in the last 90 days -- score normalized to 10',
            'details' => nil,
            'documentation' => {
              'short' => 'Determines if the project is "actively maintained".',
              'url' => 'https://github.com/ossf/scorecard/blob/main/docs/checks.md#maintained'
            }
          },
          {
            'name' => 'Code-Review',
            'score' => 9,
            'reason' => 'Found 27/30 approved changesets -- score normalized to 9',
            'details' => nil,
            'documentation' => {
              'short' => 'Determines if the project requires human code review before pull requests are merged.',
              'url' => 'https://github.com/ossf/scorecard/blob/main/docs/checks.md#code-review'
            }
          },
          {
            'name' => 'Branch-Protection',
            'score' => 0,
            'reason' => 'branch protection not enabled on development/release branches',
            'details' => ['Warn: branch protection not enabled for branch \'main\''],
            'documentation' => {
              'short' => 'Determines if the default and release branches are protected.',
              'url' => 'https://github.com/ossf/scorecard/blob/main/docs/checks.md#branch-protection'
            }
          },
          {
            'name' => 'Dangerous-Workflow',
            'score' => 0,
            'reason' => 'dangerous workflow patterns detected',
            'details' => ['Warn: dangerous pattern detected in workflow'],
            'documentation' => {
              'short' => 'Determines if the project\'s GitHub Action workflows avoid dangerous patterns.',
              'url' => 'https://github.com/ossf/scorecard/blob/main/docs/checks.md#dangerous-workflow'
            }
          },
          {
            'name' => 'Packaging',
            'score' => -1,
            'reason' => 'packaging workflow not detected',
            'details' => ['Warn: no GitHub/GitLab publishing workflow detected.'],
            'documentation' => {
              'short' => 'Determines if the project is published as a package.',
              'url' => 'https://github.com/ossf/scorecard/blob/main/docs/checks.md#packaging'
            }
          }
        ]
      }
    end
    last_synced_at { 1.hour.ago }
    association :repository
  end
end