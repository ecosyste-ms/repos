class HomeController < ApplicationController
  def index
    @hosts = Host.all.order('repositories_count DESC')
  end
end