class Api::V1::ApplicationController < ApplicationController
  after_action { pagy_headers_merge(@pagy) if @pagy }

  def default_url_options(options = {})
    Rails.env.production? ? { :protocol => "https" }.merge(options) : options
  end

  # Nested routes under repositories (tags, releases, manifests, sbom) shadow
  # repositories#show for repos whose last path segment matches the nested route
  # name. When the shorter repository_id doesn't exist, try the full path as a
  # repo name and render it. Returns true if it rendered.
  def render_shadowed_repository(repository_id, suffix)
    repo = @host.find_repository("#{repository_id}/#{suffix}".downcase)
    return false unless repo
    if repo.owner_hidden?
      render json: { error: 'Repository not found' }, status: :not_found
    else
      @repository = repo
      render 'api/v1/repositories/show'
    end
    true
  end

  def set_cache_headers
    return unless request.get? || request.head?
    expires_in 5.minutes, public: true, stale_while_revalidate: 30.minutes
    response.headers['CDN-Cache-Control'] = "max-age=#{1.hour.to_i}, stale-while-revalidate=#{4.hours.to_i}"
  end
end