class Manifest < ApplicationRecord
  belongs_to :repository, optional: true
  belongs_to :tag, optional: true
  has_many :dependencies, dependent: :delete_all

  validate :repository_xor_tag

  scope :latest, -> { order("manifests.filepath, manifests.created_at DESC").select("DISTINCT on (manifests.filepath) *") }
  scope :ecosystem, ->(ecosystem) { where('lower(manifests.ecosystem) = ?', ecosystem.try(:downcase)) }
  scope :kind, ->(kind) { where(kind: kind) }

  def repository_link
    if repository.present?
      repository.blob_url + filepath
    else
      tag.blob_url + filepath
    end
  end

  def lockfile?
    kind == 'lockfile'
  end

  def repository_xor_tag
    if repository_id.blank? && tag_id.blank?
      errors.add(:base, "Repository or Tag must be present")
    elsif repository_id.present? && tag_id.present?
      errors.add(:base, "Repository and Tag cannot both be present")
    end
  end
end
