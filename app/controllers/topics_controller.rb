class TopicsController < ApplicationController
  VALID_TOPIC_PATTERN = /\A[a-z0-9][a-z0-9\-]*\z/

  def index
    if params[:host_id]
      @host = Host.find_by_name(params[:host_id])
      @topics = @host.repositories.topics
    else
      @topics = Repository.topics
    end

    @topics = @topics.reject { |topic| Repository.blocked_topics.include?(topic[0]) }

    @pagy, @topics = pagy_array(@topics)
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