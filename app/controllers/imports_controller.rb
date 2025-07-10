class ImportsController < ApplicationController
  def index
    @pagy, imports = pagy_countless(Import.order("filename DESC"))
    @imports = imports.sort_by { |import| import.filename.scan(/\d+|[^\d]+/).map { |s| s =~ /\d/ ? s.to_i : s } }.reverse
    
    @recent_stats = {
      total: Import.where('imported_at > ?', 24.hours.ago).count,
      successful: Import.successful.where('imported_at > ?', 24.hours.ago).count,
      failed: Import.failed.where('imported_at > ?', 24.hours.ago).count,
      repositories_processed: Import.successful.where('imported_at > ?', 24.hours.ago).sum(:repositories_synced_count),
      repositories_with_releases: Import.successful.where('imported_at > ?', 24.hours.ago).sum(:releases_synced_count)
    }
  end
end