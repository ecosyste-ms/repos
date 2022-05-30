class Host < ApplicationRecord
  validates_presence_of :name, :url, :kind
  validates_uniqueness_of :name, :url

  has_many :repositories

  def to_s
    name
  end

  def sync_repository(full_name)
    repo_hash = host_instance.fetch_repository(full_name)
    return if repo_hash.blank?

    ActiveRecord::Base.transaction do
      g = repositories.find_by(uuid: repo_hash[:id])
      g = repositories.find_by('lower(full_name) = ?', repo_hash[:full_name].downcase) if g.nil?
      g = repositories.new(uuid: repo_hash[:id], full_name: repo_hash[:full_name]) if g.nil?
      g.full_name = repo_hash[:full_name] if g.full_name.downcase != repo_hash[:full_name].downcase

      g.assign_attributes(repo_hash)

      if g.changed?

        # TODO sync extra things if stuff changed

        return g.save ? g : nil
      else
        return g
      end
    end
  rescue ActiveRecord::RecordNotUnique
    nil
  end

  def host_class
    "Hosts::#{kind.capitalize}".constantize
  end

  def host_instance
    host_class.new(url)
  end
end
