class TopicsController < ApplicationController
  def index
    @pagy, @topics = pagy_array(Repository.topics)
  end

  def show
    @topic = params[:id]

    scope = Repository.includes(:host).where('topics @> ARRAY[?]::varchar[]', @topic)
    sort = params[:sort].presence || 'repositories.updated_at'
    if params[:order] == 'asc'
      scope = scope.order(Arel.sql(sort).asc.nulls_last)
    else
      scope = scope.order(Arel.sql(sort).desc.nulls_last)
    end
    
    @pagy, @repositories = pagy_countless(scope)
    @related_topics = (scope.pluck(:topics).flatten - [@topic]).inject(Hash.new(0)) { |h, e| h[e] += 1; h }.sort_by { |_, v| -v }.first(100)
  end
end