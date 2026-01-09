class Api::V1::TopicsController < Api::V1::ApplicationController
  def index
    topics = Repository.topics

    @pagy, @topics = pagy_array(topics)
    expires_in 1.day, public: true
  end

  def show
    @topic = params[:id]

    scope = Repository.topic(@topic).includes(:host)

    @related_topics = related_topics_for_scope(scope, @topic)

    scope = scope.created_after(params[:created_after]) if params[:created_after].present?
    scope = scope.updated_after(params[:updated_after]) if params[:updated_after].present?
    scope = scope.forked(params[:fork]) if params[:fork].present?
    scope = scope.archived(params[:archived]) if params[:archived].present?

    sort = params[:sort] || 'id'
    order = params[:order] || 'desc'
    sort_options = sort.split(',').zip(order.split(',')).to_h
    scope = scope.order(sort_options)

    @pagy, @repositories = pagy_countless(scope)
    fresh_when @repositories, public: true
  end
end