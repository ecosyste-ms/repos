class Api::V1::ApplicationController < ApplicationController
  MAX_PAGE = 100

  after_action { pagy_headers_merge(@pagy) if @pagy }

  def reject_deep_pagination
    return unless params[:page].to_i > MAX_PAGE
    render json: { error: "Pagination is capped at page #{MAX_PAGE}. Use the data exports at https://repos.ecosyste.ms/open-data for bulk access." }, status: :bad_request
  end

  def default_url_options(options = {})
    Rails.env.production? ? { :protocol => "https" }.merge(options) : options
  end

  # Nested routes under repositories (tags, releases, manifests, sbom) shadow
  # repositories#show for repos whose last path segment matches the nested route
  # name. When the shorter repository_id doesn't exist, try the full path as a
  # repo name and render it. Returns true if it rendered.
  def render_shadowed_repository(repository_id, suffix)
    repo = @host.find_repository("#{repository_id}/#{suffix}".downcase, previous_names: false)
    return false unless repo
    if repo.owner_hidden?
      render json: { error: 'Repository not found' }, status: :not_found
    else
      @repository = repo
      render 'api/v1/repositories/show'
    end
    true
  end

  # A previous name only matches when no current repository is named
  # repository_id or repository_id/suffix, so it can't hide a shadowed repo.
  def find_repository_unless_shadowed(repository_id, suffix)
    name = repository_id.downcase
    repo = @host.find_repository(name, previous_names: false)
    return repo if repo
    return nil if @host.find_repository("#{name}/#{suffix}", previous_names: false)
    @host.find_repository(name)
  end

  def set_cache_headers
    return unless request.get? || request.head?
    expires_in 5.minutes, public: true, stale_while_revalidate: 30.minutes
    response.headers['CDN-Cache-Control'] = "max-age=#{1.hour.to_i}, stale-while-revalidate=#{4.hours.to_i}"
  end
end