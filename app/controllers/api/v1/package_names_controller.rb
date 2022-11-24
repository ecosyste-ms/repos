class Api::V1::PackageNamesController < Api::V1::ApplicationController
  def docker
    names = Manifest.where(ecosystem: 'docker').joins(:dependencies).pluck('DISTINCT(dependencies.package_name)')

    @uniq_names = names.reject{|n| ['.', '{', '$', '<'].any?{|s| n.include?(s) }}.map do |n|
      if n.include?('/')
        n
      else
        "library/#{n}"
      end
    end.sort.uniq
    
    render json: @uniq_names
  end
end
