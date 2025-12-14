class ApplicationController < ActionController::Base
  include Pagy::Backend
  before_action :set_locale

  skip_before_action :verify_authenticity_token

  after_action lambda {
    request.session_options[:skip] = true
  }

  def set_locale
    I18n.locale = http_accept_language.compatible_language_from(I18n.available_locales)
  end

  def find_host
    find_host_by_param(:host_id)
  end

  def find_host_by_id
    find_host_by_param(:id)
  end

  def find_host_by_param(param_name)
    host_param = params[param_name]
    @host = Host.find_by_name!(host_param)
    unless @host.name.downcase == host_param.downcase
      safe_params = request.query_parameters.except(:controller, :action, :host, :port, :protocol)
      redirect_params = safe_params.merge(param_name => @host.name)
      redirect_to url_for(redirect_params.merge(only_path: true)), status: :moved_permanently
    end
  end
end
