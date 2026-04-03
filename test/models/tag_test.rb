require "test_helper"

class TagTest < ActiveSupport::TestCase
  context 'associations' do
    should belong_to(:repository)
  end

  context 'purl method' do
    setup do
      @host = Host.create!(name: 'GitHub', url: 'https://github.com', kind: 'github')
      @repository = Repository.create!(
        full_name: 'rails/rails',
        owner: 'rails',
        uuid: '123',
        host: @host,
        created_at: Time.now,
        updated_at: Time.now
      )
      @tag = Tag.create!(
        name: 'v1.0.0',
        sha: 'abc123',
        repository: @repository
      )
    end

    should 'generate correct purl for tag with version' do
      expected_purl = "pkg:github/rails/rails@v1.0.0"
      assert_equal expected_purl, @tag.purl
    end
  end

  context 'delete_old_manifests' do
    setup do
      @host = FactoryBot.create(:github_host)
      @repository = FactoryBot.create(:repository, host: @host, full_name: 'test/delmanifests', owner: 'test')
      @tag = FactoryBot.create(:tag, repository: @repository, name: 'v2.0.0', sha: 'def456')
    end

    should 'delete manifests not present in new list' do
      old_manifest = Manifest.create!(tag: @tag, ecosystem: 'npm', filepath: 'package.json', kind: 'manifest')
      keep_manifest = Manifest.create!(tag: @tag, ecosystem: 'rubygems', filepath: 'Gemfile', kind: 'manifest')

      new_manifests = [{ platform: 'rubygems', path: 'Gemfile' }]

      @tag.delete_old_manifests(new_manifests)

      assert_not Manifest.exists?(old_manifest.id)
      assert Manifest.exists?(keep_manifest.id)
    end

    should 'delete dependencies belonging to removed manifests' do
      old_manifest = Manifest.create!(tag: @tag, ecosystem: 'npm', filepath: 'package.json', kind: 'manifest')
      dep = Dependency.create!(manifest: old_manifest, repository: @repository, ecosystem: 'npm', package_name: 'lodash', requirements: '^4.0', kind: 'runtime')

      new_manifests = []

      @tag.delete_old_manifests(new_manifests)

      assert_not Manifest.exists?(old_manifest.id)
      assert_not Dependency.exists?(dep.id)
    end

    should 'do nothing when all manifests match' do
      keep = Manifest.create!(tag: @tag, ecosystem: 'npm', filepath: 'package.json', kind: 'manifest')

      new_manifests = [{ platform: 'npm', path: 'package.json' }]

      @tag.delete_old_manifests(new_manifests)

      assert Manifest.exists?(keep.id)
    end
  end

  context 'parse_dependencies method' do
    setup do
      @host = FactoryBot.create(:github_host)
      @repository = FactoryBot.create(:repository, host: @host, full_name: 'test/repo', owner: 'test')
      @tag = FactoryBot.create(:tag, repository: @repository, name: 'v1.0.0', sha: 'abc123')
    end

    should 'clear dependency_job_id and start new job when 404 is returned' do
      @tag.update_column(:dependency_job_id, 'old-job-id')

      first_response = mock('first_response')
      first_response.stubs(:status).returns(404)
      first_response.stubs(:success?).returns(false)

      second_response = mock('second_response')
      second_response.stubs(:status).returns(200)
      second_response.stubs(:success?).returns(true)
      second_response.stubs(:body).returns({ id: 'new-job-id', status: 'pending' }.to_json)

      conn = mock('connection')
      conn.expects(:get).with("/api/v1/jobs/old-job-id").returns(first_response)
      conn.expects(:post).with("/api/v1/jobs?url=#{CGI.escape(@tag.download_url)}").returns(second_response)

      @tag.stubs(:ecosystem_connection).returns(conn)

      @tag.parse_dependencies

      @tag.reload
      assert_equal 'new-job-id', @tag.dependency_job_id
    end

    should 'not clear dependency_job_id when response is not 404' do
      @tag.update_column(:dependency_job_id, 'existing-job-id')

      response = mock('response')
      response.stubs(:status).returns(500)
      response.stubs(:success?).returns(false)

      conn = mock('connection')
      conn.expects(:get).with("/api/v1/jobs/existing-job-id").returns(response)
      conn.expects(:post).never

      @tag.stubs(:ecosystem_connection).returns(conn)

      @tag.parse_dependencies

      @tag.reload
      assert_equal 'existing-job-id', @tag.dependency_job_id
    end

    should 'process successfully when job exists' do
      @tag.update_column(:dependency_job_id, 'existing-job-id')

      response = mock('response')
      response.stubs(:status).returns(200)
      response.stubs(:success?).returns(true)
      response.stubs(:body).returns({ id: 'existing-job-id', status: 'complete', results: { manifests: [] } }.to_json)

      conn = mock('connection')
      conn.expects(:get).with("/api/v1/jobs/existing-job-id").returns(response)

      @tag.stubs(:ecosystem_connection).returns(conn)

      @tag.parse_dependencies

      @tag.reload
      assert_nil @tag.dependency_job_id
      assert_not_nil @tag.dependencies_parsed_at
    end
  end
end
