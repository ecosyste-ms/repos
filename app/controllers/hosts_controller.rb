class HostsController < ApplicationController
  before_action :find_host_by_id, only: [:show, :topics, :topic]

  def related_topics_for_scope(scope, exclude_topic)
    repo_ids = scope.reorder('stargazers_count DESC NULLS LAST').limit(1000).select(:id)

    sql = Repository.sanitize_sql_array([<<~SQL, exclude_topic])
      SELECT topic, COUNT(*) as cnt
      FROM (
        SELECT unnest(topics) as topic
        FROM repositories
        WHERE id IN (#{repo_ids.to_sql})
          AND topics IS NOT NULL
      ) t
      WHERE topic != ? AND topic != ''
      GROUP BY topic
      ORDER BY cnt DESC, topic ASC
      LIMIT 100
    SQL

    Repository.connection.select_rows(sql, "related_topics")
  end

  def index
    redirect_to root_path
  end

  def show

    scope = @host.repositories

    sort = params[:sort].presence || 'id'
    if params[:order] == 'asc'
      scope = scope.order(Arel.sql(sort).asc.nulls_last)
    else
      scope = scope.order(Arel.sql(sort).desc.nulls_last)
    end

    @pagy, @repositories = pagy_countless(scope)
    expires_in 1.day, public: true
  end

  def kind
    @kind = params[:id]
    @hosts = Host.where(kind: @kind).order('repositories_count DESC')
    @pagy, @hosts = pagy(@hosts)
    raise ActiveRecord::RecordNotFound if @hosts.empty?
  end

  def topics
    topics = @host.topics.reject { |topic| Repository.blocked_topics.include?(topic[0]) }
    @pagy, @topics = pagy_array(topics)
  end

  def topic
    raise ActiveRecord::RecordNotFound if Repository.blocked_topics.include?(params[:topic])

    scope = @host.repositories.where.not(last_synced_at:nil)

    scope = scope.topic(params[:topic])
    
    if params[:sort].present? || params[:order].present?
      sort = params[:sort].presence || 'updated_at'
      if params[:order] == 'asc'
        scope = scope.order(Arel.sql(sort).asc.nulls_last)
      else
        scope = scope.order(Arel.sql(sort).desc.nulls_last)
      end
    else
      scope = scope.order('updated_at desc')
    end

    @related_topics = related_topics_for_scope(scope, params[:topic])

    raise ActiveRecord::RecordNotFound if scope.empty?

    @pagy, @repositories = pagy_countless(scope)
    expires_in 1.day, public: true
  end
end