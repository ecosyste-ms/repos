require 'rails_helper'

RSpec.describe GharchiveImporter do
  let(:host) { create(:host, name: 'GitHub') }
  let(:importer) { described_class.new(host) }
  
  describe '#extract_repository_data' do
    context 'with PushEvent' do
      let(:events) do
        [{
          'type' => 'PushEvent',
          'repo' => { 'id' => 123456, 'name' => 'owner/repo' },
          'created_at' => '2025-01-09T12:00:00Z',
          'payload' => {
            'ref' => 'refs/heads/main'
          }
        }]
      end
      
      it 'extracts basic repository data and branch info' do
        data = importer.send(:extract_repository_data, events)
        
        expect(data[:uuid]).to eq('123456')
        expect(data[:owner]).to eq('owner')
        expect(data[:default_branch]).to eq('main')
        expect(data[:pushed_at]).to be_a(Time)
      end
    end
    
    context 'with CreateEvent' do
      let(:events) do
        [{
          'type' => 'CreateEvent',
          'repo' => { 'id' => 123456, 'name' => 'owner/repo' },
          'created_at' => '2025-01-09T12:00:00Z',
          'payload' => {
            'ref_type' => 'repository',
            'master_branch' => 'main',
            'description' => 'A test repository'
          }
        }]
      end
      
      it 'extracts repository description and default branch' do
        data = importer.send(:extract_repository_data, events)
        
        expect(data[:description]).to eq('A test repository')
        expect(data[:default_branch]).to eq('main')
      end
    end
    
    context 'with ForkEvent' do
      let(:events) do
        [{
          'type' => 'ForkEvent',
          'repo' => { 'id' => 123456, 'name' => 'owner/repo' },
          'created_at' => '2025-01-09T12:00:00Z',
          'payload' => {
            'forkee' => {
              'full_name' => 'forker/repo',
              'fork' => true
            }
          }
        }]
      end
      
      it 'does not mark parent repository as fork' do
        data = importer.send(:extract_repository_data, events)
        
        expect(data[:fork]).to be_nil
      end
    end
    
    context 'with org event' do
      let(:events) do
        [{
          'type' => 'PushEvent',
          'repo' => { 'id' => 123456, 'name' => 'org/repo' },
          'org' => { 'login' => 'org' },
          'created_at' => '2025-01-09T12:00:00Z',
          'payload' => {}
        }]
      end
      
      it 'uses org login as owner' do
        data = importer.send(:extract_repository_data, events)
        
        expect(data[:owner]).to eq('org')
      end
    end
  end
  
  describe '#find_or_create_repository' do
    context 'when repository exists' do
      let!(:repository) { create(:repository, host: host, full_name: 'owner/repo', uuid: '123456') }
      
      it 'finds existing repository by uuid' do
        result = importer.send(:find_or_create_repository, 'owner/repo', { uuid: '123456' })
        expect(result).to eq(repository)
      end
      
      it 'finds existing repository by full_name' do
        result = importer.send(:find_or_create_repository, 'owner/repo', {})
        expect(result).to eq(repository)
      end
    end
    
    context 'when repository does not exist' do
      it 'creates new repository with event data' do
        event_data = {
          uuid: '123456',
          owner: 'owner',
          description: 'Test repo',
          default_branch: 'main',
          language: 'Ruby'
        }
        
        expect {
          importer.send(:find_or_create_repository, 'owner/repo', event_data)
        }.to change(Repository, :count).by(1)
        
        repo = Repository.last
        expect(repo.uuid).to eq('123456')
        expect(repo.full_name).to eq('owner/repo')
        expect(repo.description).to eq('Test repo')
        expect(repo.default_branch).to eq('main')
        expect(repo.language).to eq('Ruby')
      end
      
      it 'skips creation for fork repositories' do
        event_data = { uuid: '123456', fork: true }
        
        expect {
          result = importer.send(:find_or_create_repository, 'owner/repo', event_data)
          expect(result).to be_nil
        }.not_to change(Repository, :count)
      end
      
      it 'skips creation for archived repositories' do
        event_data = { uuid: '123456', archived: true }
        
        expect {
          result = importer.send(:find_or_create_repository, 'owner/repo', event_data)
          expect(result).to be_nil
        }.not_to change(Repository, :count)
      end
    end
  end
  
  describe '#process_release_events' do
    let(:repository) { create(:repository, host: host) }
    let(:release_events) do
      [{
        'payload' => {
          'action' => 'published',
          'release' => {
            'id' => 987654,
            'tag_name' => 'v1.0.0',
            'name' => 'Version 1.0.0',
            'body' => 'First release',
            'draft' => false,
            'prerelease' => false,
            'created_at' => '2025-01-09T12:00:00Z',
            'published_at' => '2025-01-09T12:00:00Z',
            'author' => { 'login' => 'author' },
            'target_commitish' => 'main'
          }
        }
      }]
    end
    
    it 'creates release from event data' do
      expect {
        importer.send(:process_release_events, repository, release_events)
      }.to change(repository.releases, :count).by(1)
      
      release = repository.releases.last
      expect(release.uuid).to eq('987654')
      expect(release.tag_name).to eq('v1.0.0')
      expect(release.name).to eq('Version 1.0.0')
      expect(release.body).to eq('First release')
      expect(release.author).to eq('author')
    end
    
    it 'updates existing release' do
      existing = create(:release, repository: repository, uuid: '987654', name: 'Old name')
      
      expect {
        importer.send(:process_release_events, repository, release_events)
      }.not_to change(repository.releases, :count)
      
      existing.reload
      expect(existing.name).to eq('Version 1.0.0')
    end
    
    it 'skips non-published releases' do
      release_events[0]['payload']['action'] = 'created'
      
      expect {
        importer.send(:process_release_events, repository, release_events)
      }.not_to change(repository.releases, :count)
    end
  end
  
  describe '#process_repository_events' do
    context 'with mixed events' do
      let(:events) do
        [
          {
            'type' => 'PushEvent',
            'repo' => { 'id' => 123456, 'name' => 'owner/repo' },
            'created_at' => '2025-01-09T12:00:00Z',
            'payload' => { 'ref' => 'refs/heads/main' }
          },
          {
            'type' => 'ReleaseEvent',
            'repo' => { 'id' => 123456, 'name' => 'owner/repo' },
            'created_at' => '2025-01-09T12:01:00Z',
            'payload' => {
              'action' => 'published',
              'release' => {
                'id' => 987654,
                'tag_name' => 'v1.0.0',
                'name' => 'Version 1.0.0'
              }
            }
          }
        ]
      end
      
      it 'processes events and updates stats' do
        allow(repository = double).to receive(:id).and_return(1)
        allow(repository).to receive(:pushed_at).and_return(nil)
        allow(repository).to receive(:update_column)
        allow(repository).to receive(:sync_async)
        allow(repository).to receive(:download_tags_async)
        allow(repository).to receive(:releases).and_return(double(find_by: nil, create!: true))
        
        allow(importer).to receive(:find_or_create_repository).and_return(repository)
        
        importer.send(:process_repository_events, 'owner/repo', events)
        
        expect(importer.import_stats[:push_events_count]).to eq(1)
        expect(importer.import_stats[:release_events_count]).to eq(1)
        expect(importer.import_stats[:repositories_synced_count]).to eq(1)
        expect(importer.import_stats[:releases_synced_count]).to eq(1)
      end
    end
  end
  
  describe '#import_hour' do
    before do
      stub_request(:get, /data.gharchive.org/)
        .to_return(
          status: 200,
          body: Zlib::Deflate.deflate(
            [
              { type: 'PushEvent', repo: { id: 123, name: 'test/repo' }, created_at: '2025-01-09T12:00:00Z', payload: {} },
              { type: 'IssueEvent', repo: { id: 456, name: 'other/repo' }, created_at: '2025-01-09T12:00:00Z', payload: {} }
            ].map(&:to_json).join("\n")
          ),
          headers: { 'Content-Type' => 'application/gzip' }
        )
    end
    
    it 'imports events for specified hour' do
      expect {
        result = importer.import_hour(Date.new(2025, 1, 9), 12)
        expect(result).to be true
      }.to change(Import, :count).by(1)
      
      import = Import.last
      expect(import.filename).to eq('2025-01-09-12.json.gz')
      expect(import.success).to be true
      expect(import.push_events_count).to eq(1)
    end
    
    it 'skips if already imported' do
      create(:import, filename: '2025-01-09-12.json.gz', success: true)
      
      expect {
        result = importer.import_hour(Date.new(2025, 1, 9), 12)
        expect(result).to be true
      }.not_to change(Import, :count)
    end
    
    it 'records failure on error' do
      stub_request(:get, /data.gharchive.org/).to_return(status: 404)
      
      expect {
        result = importer.import_hour(Date.new(2025, 1, 9), 12)
        expect(result).to be false
      }.to change(Import, :count).by(1)
      
      import = Import.last
      expect(import.success).to be false
      expect(import.error_message).to include('Failed to download')
    end
  end
end