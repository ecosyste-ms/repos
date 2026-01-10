class Api::V1::TopicsController < Api::V1::ApplicationController
  def index
    scope = Topic.where.not(name: Repository.blocked_topics).by_count

    @pagy, @topics = pagy(scope)
    expires_in 1.day, public: true
  end

  def show
    @topic = params[:id]
    # TODO(DB_PERF): api/topics#show disabled 2026-01-10
    # topics @> ARRAY query on 297M rows is slow even with GIN index
    # Needs: composite index, materialized view, or pre-computed topic pages
    # Returning empty results instead of running slow query
    @repositories = []
    @related_topics = []
    @pagy = Pagy.new(count: 0, page: 1)
  end
end