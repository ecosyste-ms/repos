class Export < ApplicationRecord
  validates_presence_of :date, :bucket_name, :repositories_count

  def download_url
    "https://#{bucket_name}.s3.amazonaws.com/repos-#{date}.tar.gz"
  end

  def latest?
    self == Export.order("date DESC").first
  end
end
