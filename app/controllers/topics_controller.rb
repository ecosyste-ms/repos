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
    @topic = params[:id]

    raise ActiveRecord::RecordNotFound unless @topic.match?(VALID_TOPIC_PATTERN)
    raise ActiveRecord::RecordNotFound if Repository.blocked_topics.include?(@topic)

    if params[:host_id]
      @host = Host.find_by_name(params[:host_id])
      scope = @host.repositories.includes(:host).where('topics @> ARRAY[?]::varchar[]', @topic)
    else
      scope = Repository.includes(:host).where('topics @> ARRAY[?]::varchar[]', @topic)
    end

    @related_topics = related_topics_for_scope(scope, @topic)

    scope = scope.order('stargazers_count DESC NULLS LAST, pushed_at DESC NULLS LAST, full_name ASC NULLS LAST')

    @pagy, @repositories = pagy_countless(scope)

    raise ActiveRecord::RecordNotFound if @repositories.empty?

    expires_in 1.day, public: true
  end
end