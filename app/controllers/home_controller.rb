class HomeController < ApplicationController
  def index
    @hosts = Host.all
  end
end