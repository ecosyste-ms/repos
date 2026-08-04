require 'test_helper'
require 'rake'

class OwnersRakeTest < ActiveSupport::TestCase
  setup do
    Rails.application.load_tasks unless Rake::Task.task_defined?('owners:backfill_funding')
    @host = FactoryBot.create(:github_host)
  end

  test 'backfill_funding copies .github repo funding into owner metadata' do
    owner = FactoryBot.create(:owner, host: @host, login: 'acme', metadata: { 'has_sponsors_listing' => true })
    FactoryBot.create(:repository, host: @host, full_name: 'acme/.github', owner: 'acme',
                      metadata: { 'funding' => { 'github' => ['acme'] } })

    capture_io { Rake::Task['owners:backfill_funding'].execute }

    owner.reload
    assert_equal({ 'github' => ['acme'] }, owner.metadata['funding'])
    assert_equal true, owner.metadata['has_sponsors_listing']
  end

  test 'backfill_funding leaves owners without a .github repo untouched' do
    owner = FactoryBot.create(:owner, host: @host, login: 'nofunding', metadata: { 'has_sponsors_listing' => false })

    capture_io { Rake::Task['owners:backfill_funding'].execute }

    assert_nil owner.reload.metadata['funding']
  end
end
