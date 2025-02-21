module ApplicationHelper
  include Pagy::Frontend
  include SanitizeUrl

  def sort_by_semver_range(hash, limit)
    hash.sort_by{|_k,v| -v}
               .first(limit)
               .sort_by{|k,_v|
                 k.gsub(/\~|\>|\<|\^|\=|\*|\s/,'')
                 .gsub('-','.')
                 .split('.').map{|i| i.to_i}
               }.reverse
  end

  def download_period(downloads_period)
    case downloads_period
    when "last-month"
      "last month"
    when "total"
      "total"
    end
  end

  def sanitize_user_url(url)
    return unless url && url.is_a?(String)
    return unless url =~ /\A#{URI::regexp}\z/
    sanitize_url(url, :schemes => ['http', 'https'])
  end

  def meta_description
    @meta_description || app_description
  end

  def meta_title
    [@meta_title, "Ecosyste.ms: Repos"].compact.join(" | ")
  end

  def app_name
    "Repos"
  end

  def app_description
    "An open API service providing repository metadata for many open source software ecosystems."
  end
end
