class ApplicationController < ActionController::Base
  include Pagy::Backend
  before_action :set_locale
  before_action :set_cache_headers

  skip_before_action :verify_authenticity_token

  after_action lambda {
    request.session_options[:skip] = true
  }

  def set_locale
    I18n.locale = http_accept_language.compatible_language_from(I18n.available_locales)
  end

  def set_cache_headers
    return unless request.get? || request.head?
    expires_in 5.minutes, public: true, stale_while_revalidate: 1.hour
    response.headers['CDN-Cache-Control'] = "max-age=#{4.hours.to_i}, stale-while-revalidate=#{1.day.to_i}"
  end

  def find_host
    find_host_by_param(:host_id)
  end

  def find_host_by_id
    find_host_by_param(:id)
  end

  def find_host_by_param(param_name)
    host_param = params[param_name]
    @host = Host.find_by_name!(host_param)
    unless @host.name.downcase == host_param.downcase
      safe_params = request.query_parameters.except(:controller, :action, :host, :port, :protocol)
      redirect_params = safe_params.merge(param_name => @host.name)
      redirect_to url_for(redirect_params.merge(only_path: true)), status: :moved_permanently
    end
  end

  def related_topics_for_scope(scope, exclude_topic)
    # TODO(DB_PERF): related_topics disabled 2026-01-10
    # unnest(topics) query causing DB performance issues
    return []
    repo_ids = scope.reorder('stargazers_count DESC NULLS LAST').limit(1000).pluck(:id)
    return [] if repo_ids.empty?

    sql = Repository.sanitize_sql_array([<<~SQL, repo_ids, exclude_topic])
      SELECT topic, COUNT(*) as cnt
      FROM (
        SELECT unnest(topics) as topic
        FROM repositories
        WHERE id IN (?)
          AND topics IS NOT NULL
      ) t
      WHERE topic != ? AND topic != ''
      GROUP BY topic
      ORDER BY cnt DESC, topic ASC
      LIMIT 100
    SQL

    Repository.connection.select_rows(sql, "related_topics")
  end
end
