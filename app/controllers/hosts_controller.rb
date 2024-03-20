class HostsController < ApplicationController
  def index
    redirect_to root_path
  end
  
  def show
    @host = Host.find_by_name!(params[:id])

    scope = @host.repositories#.where.not(last_synced_at:nil)

    if params[:sort].present? || params[:order].present?
      sort = params[:sort].presence || 'updated_at'
      if params[:order] == 'asc'
        scope = scope.order(Arel.sql(sort).asc.nulls_last)
      else
        scope = scope.order(Arel.sql(sort).desc.nulls_last)
      end
    else
      #scope = scope.order('updated_at desc')
    end

    @pagy, @repositories = pagy_countless(scope)
  end

  def kind
    @kind = params[:id]
    @hosts = Host.where(kind: @kind).order('repositories_count DESC')
    @pagy, @hosts = pagy(@hosts)
    raise ActiveRecord::RecordNotFound if @hosts.empty?
  end

  def topic
    @host = Host.find_by_name!(params[:id])

    scope = @host.repositories.where.not(last_synced_at:nil)

    scope = scope.topic(params[:topic])
    
    if params[:sort].present? || params[:order].present?
      sort = params[:sort].presence || 'updated_at'
      if params[:order] == 'asc'
        scope = scope.order(Arel.sql(sort).asc.nulls_last)
      else
        scope = scope.order(Arel.sql(sort).desc.nulls_last)
      end
    else
      scope = scope.order('updated_at desc')
    end

    @related_topics = (scope.pluck(:topics).flatten - [@keyword]).inject(Hash.new(0)) { |h, e| h[e] += 1; h }.sort_by { |_, v| -v }.first(100)

    @pagy, @repositories = pagy(scope)
  end
end