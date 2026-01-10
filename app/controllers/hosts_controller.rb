class HostsController < ApplicationController
  before_action :find_host_by_id, only: [:show, :topics, :topic]

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
    # TODO(DB_PERF): hosts#topic disabled 2026-01-10
    # topics @> ARRAY query on 297M rows is slow even with GIN index
    # Needs: composite index, materialized view, or pre-computed topic pages
    render plain: "Topic pages temporarily unavailable", status: :service_unavailable
  end
end