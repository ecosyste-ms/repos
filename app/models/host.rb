class Host < ApplicationRecord
  validates_presence_of :name, :url, :kind
  validates_uniqueness_of :name, :url

  has_many :repositories

  def to_s
    name
  end

  def sync_repository(full_name)
    json = host_instance.fetch_repository(full_name)
  end

  def host_class
    "Host::#{kind.capitalize}".constantize
  end

  def host_instance
    host_class.new(url)
  end
end
