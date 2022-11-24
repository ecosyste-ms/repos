class Api::V1::PackageNamesController < Api::V1::ApplicationController
  def docker
    names = Manifest.where(ecosystem: 'docker').joins(:dependencies).pluck('DISTINCT(dependencies.package_name)')

    @unique_names = names.reject{|n| ['.', '{', '$', '<'].any?{|s| n.include?(s) }}.map do |n|
      if n.include?('/')
        n
      else
        "library/#{n}"
      end
    end.sort.uniq
    
    render json: @unique_names
  end

  def actions
    names = Manifest.where(ecosystem: 'actions').joins(:dependencies).pluck('DISTINCT(dependencies.package_name)')
    @unique_names = names.reject do |n|
      n.match?(/^[\W\.]/) || n.split('/').length != 2 || n.match?(/:/)
    end.map{|n| n.split('@').last}.uniq.sort

    render json: @unique_names
  end

  def swiftpm
    names = Manifest.where(ecosystem: 'swiftpm').joins(:dependencies).pluck('DISTINCT(dependencies.package_name)')
    @unique_names = names.reject do |n|
      n.match?(/^\//)
    end.map{|n| n.split('@').last}.uniq.sort

    render json: @unique_names
  end

  def carthage
    names = Manifest.where(ecosystem: 'carthage').joins(:dependencies).pluck('DISTINCT(dependencies.package_name)')
    @unique_names = names.compact.reject do |n|
      n.match?(/^[\W\.]/) || n.split('/').length != 2 || n.match?(/:/)
    end.map{|n| n.split('@').last}.uniq.sort

    render json: @unique_names
  end

  def meteor
    names = Manifest.where(ecosystem: 'meteor').joins(:dependencies).pluck('DISTINCT(dependencies.package_name)')
    @unique_names = names.compact.reject do |n|
      n.match?(/^[\W]/) || n.include?('.')
    end.uniq.sort

    render json: @unique_names
  end
end
