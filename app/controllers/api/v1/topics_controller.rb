class Api::V1::TopicsController < Api::V1::ApplicationController
  def index
    topics = Repository.topics

    @pagy, @topics = pagy_array(topics)
    expires_in 1.day, public: true
  end

  def show
    @topic = params[:id]

    scope = Repository.topic(@topic).includes(:host)

    @related_topics = (scope.order('stargazers_count DESC NULLS LAST').limit(1000).pluck(:topics).flatten - [@topic]).inject(Hash.new(0)) { |h, e| h[e] += 1; h }.sort_by { |_, v| -v }.first(100)

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