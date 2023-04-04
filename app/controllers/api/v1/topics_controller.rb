class Api::V1::TopicsController < Api::V1::ApplicationController
  def index
    topics = Repository.topics

    @pagy, @topics = pagy_array(topics)
  end

  def show
    @topic = params[:id]

    scope = Repository.topic(@topic).includes(:host)

    @related_topics = (scope.pluck(:topics).flatten - [@topic]).inject(Hash.new(0)) { |h, e| h[e] += 1; h }.sort_by { |_, v| -v }.first(100)
    @pagy, @repositories = pagy(scope)
  end
end