module ApplicationHelper
  include Pagy::Frontend

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
end
