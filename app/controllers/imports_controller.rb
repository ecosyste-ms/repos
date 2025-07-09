class ImportsController < ApplicationController
  def index
    @pagy, @imports = pagy(Import.recent)
    
    # Calculate stats for last 24 hours
    @recent_stats = {
      total: Import.where('imported_at > ?', 24.hours.ago).count,
      successful: Import.successful.where('imported_at > ?', 24.hours.ago).count,
      failed: Import.failed.where('imported_at > ?', 24.hours.ago).count,
      repositories_processed: Import.successful.where('imported_at > ?', 24.hours.ago).sum(:repositories_processed),
      repositories_with_releases: Import.successful.where('imported_at > ?', 24.hours.ago).sum(:repositories_with_releases)
    }
  end
end