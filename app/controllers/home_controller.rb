class HomeController < ApplicationController
  def index
    @hosts = Host.all.order('repositories_count DESC').where('repositories_count > 0')
  end
end