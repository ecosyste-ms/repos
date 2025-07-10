class Import < ApplicationRecord
  validates :filename, presence: true, uniqueness: true
  
  scope :successful, -> { where(success: true) }
  scope :failed, -> { where(success: false) }
  scope :recent, -> { order(imported_at: :desc) }
  
  def self.filename_for(date, hour)
    "#{date.strftime('%Y-%m-%d')}-#{hour}.json.gz"
  end
  
  def self.already_imported?(date, hour)
    exists?(filename: filename_for(date, hour), success: true)
  end
  
  def self.create_from_import(date, hour, stats = {})
    import = find_or_initialize_by(filename: filename_for(date, hour))
    import.update!(
      imported_at: Time.current,
      repositories_synced_count: stats[:repositories_processed] || 0,
      releases_synced_count: stats[:repositories_with_releases] || 0,
      success: true,
      error_message: nil # Clear any previous error
    )
    import
  end
  
  def self.record_failure(date, hour, error_message)
    import = find_or_initialize_by(filename: filename_for(date, hour))
    import.update!(
      imported_at: Time.current,
      success: false,
      error_message: error_message
    )
  end
  
  def retry!
    # Re-run the import for this specific hour
    date_parts = filename.match(/(\d{4}-\d{2}-\d{2})-(\d+)\.json\.gz/)
    return false unless date_parts
    
    date = Date.parse(date_parts[1])
    hour = date_parts[2].to_i
    
    host = Host.find_by(name: 'GitHub')
    importer = GharchiveImporter.new(host)
    importer.import_hour(date, hour)
    
    true
  rescue => e
    update!(error_message: e.message)
    false
  end
  
  def url
    "https://data.gharchive.org/#{filename}"
  end
end
