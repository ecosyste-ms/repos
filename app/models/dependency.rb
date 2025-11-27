class Dependency < ApplicationRecord
  belongs_to :repository
  belongs_to :manifest

  scope :ecosystem, ->(ecosystem) { where(ecosystem: ecosystem.downcase) }
  scope :kind, ->(kind) { where(kind: kind) }
  scope :active, -> { joins(:repository).where(repositories: {archived: false}) }
  scope :source, -> { joins(:repository).where(repositories: {fork: false}) }
  scope :direct, -> { where(direct: true) }
  scope :transitive, -> { where(direct: false) }

  delegate :filepath, to: :manifest

  def package_usage
    @package_usage ||= PackageUsage.where(ecosystem: ecosystem, name: package_name).first
  end

  def has_funding_links?
    package_usage.try(:funding_links).try(:any?) || false
  end

  def package_name
    read_attribute(:package_name).try(:tr, " \n\t\r", '')
  end

  def direct?
    manifest.kind == 'manifest'
  end

  def incompatible_license?
    compatible_license? == false
  end
  
  def semantic_requirements
    case ecosystem.downcase
    when 'elm'
      numbers = requirements.split('<= v')
      ">=#{numbers[0].strip} #{numbers[1].strip}"
    else
      requirements
    end
  end

  def valid_requirements?
    !!SemanticRange.valid_range(semantic_requirements)
  end
end
