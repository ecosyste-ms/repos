class TopicsController < ApplicationController
  def index
    @pagy, @topics = pagy_array(Repository.topics)
    expires_in 1.day, public: true
  end

  def show
    @topic = params[:id]

    scope = Repository.includes(:host).where('topics @> ARRAY[?]::varchar[]', @topic)

    @related_topics = (scope.pluck(:topics).flatten - [@topic]).inject(Hash.new(0)) { |h, e| h[e] += 1; h }.sort_by { |_, v| -v }.first(100)

    scope = scope.order('stargazers_count DESC NULLS LAST, pushed_at DESC NULLS LAST, full_name ASC NULLS LAST')

    @pagy, @repositories = pagy_countless(scope)
    expires_in 1.day, public: true
  end
end