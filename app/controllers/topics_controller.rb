class TopicsController < ApplicationController
  VALID_TOPIC_PATTERN = /\A[a-z0-9][a-z0-9\-]*\z/

  def index
    if params[:host_id]
      @host = Host.find_by_name(params[:host_id])
      scope = @host.topics.where.not(name: Repository.blocked_topics).by_count
    else
      scope = Topic.where.not(name: Repository.blocked_topics).by_count
    end

    @pagy, @topics = pagy(scope)
    expires_in 1.day, public: true
  end

  def show
    # TODO(DB_PERF): topics#show disabled 2026-01-10
    # topics @> ARRAY query on 297M rows is slow even with GIN index
    # Combined with ORDER BY stargazers_count, it causes 15+ minute queries
    # Needs: composite index, materialized view, or pre-computed topic pages
    render plain: "Topic pages temporarily unavailable", status: :service_unavailable
  end
end