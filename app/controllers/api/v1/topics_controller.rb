class Api::V1::TopicsController < Api::V1::ApplicationController
  def index
    topics = Repository.topics

    @pagy, @topics = pagy_array(topics)
    fresh_when @topics, public: true
  end

  def show
    @topic = params[:id]

    scope = Repository.topic(@topic).includes(:host)

    @related_topics = (scope.pluck(:topics).flatten - [@topic]).inject(Hash.new(0)) { |h, e| h[e] += 1; h }.sort_by { |_, v| -v }.first(100)

    scope = scope.created_after(params[:created_after]) if params[:created_after].present?
    scope = scope.updated_after(params[:updated_after]) if params[:updated_after].present?
    scope = scope.forked(params[:fork]) if params[:fork].present?
    scope = scope.archived(params[:archived]) if params[:archived].present?

    if params[:sort].present? || params[:order].present?
      sort = params[:sort] || 'last_synced_at'
      order = params[:order] || 'desc'
      sort_options = sort.split(',').zip(order.split(',')).to_h
      scope = scope.order(sort_options)
    end

    @pagy, @repositories = pagy(scope)
    fresh_when @repositories, public: true
  end
end