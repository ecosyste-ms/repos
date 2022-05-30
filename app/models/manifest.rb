class Manifest < ApplicationRecord
  belongs_to :repository
  has_many :dependencies, dependent: :delete_all

  scope :latest, -> { order("manifests.filepath, manifests.created_at DESC").select("DISTINCT on (manifests.filepath) *") }
  scope :ecosystem, ->(ecosystem) { where('lower(manifests.ecosystem) = ?', ecosystem.try(:downcase)) }
  scope :kind, ->(kind) { where(kind: kind) }

  def repository_link
    repository.blob_url + filepath
  end

  def lockfile?
    kind == 'lockfile'
  end
end
