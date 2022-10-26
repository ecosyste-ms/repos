require 'sidekiq/web'

Sidekiq::Web.use Rack::Auth::Basic do |username, password|
  ActiveSupport::SecurityUtils.secure_compare(::Digest::SHA256.hexdigest(username), ::Digest::SHA256.hexdigest(ENV["SIDEKIQ_USERNAME"])) &
    ActiveSupport::SecurityUtils.secure_compare(::Digest::SHA256.hexdigest(password), ::Digest::SHA256.hexdigest(ENV["SIDEKIQ_PASSWORD"]))
end if Rails.env.production?

Rails.application.routes.draw do
  mount Rswag::Ui::Engine => '/docs'
  mount Rswag::Api::Engine => '/docs'
  
  mount Sidekiq::Web => "/sidekiq"
  mount PgHero::Engine, at: "pghero"

  namespace :api, :defaults => {:format => :json} do
    namespace :v1 do

      get 'usage', to: 'usage#index', as: :usage_index
      get 'usage/:ecosystem', to: 'usage#ecosystem', as: :ecosystem_usage
      get 'usage/:ecosystem/:name', to: 'usage#show', as: :usage, constraints: { name: /.*/ }

      get 'repositories/lookup', to: 'repositories#lookup', as: :repositories_lookup
      resources :hosts, constraints: { id: /.*/ }, only: [:index, :show] do
        resources :repositories, constraints: { id: /.*/ }, only: [:index, :show] do
          resources :tags
          resources :manifests
        end
        
        member do
          get :repository_names, to: 'repositories#names', as: :repository_names
        end
      end
    end
  end

  get '/usage', to: 'usage#index', as: :usage_index
  get 'usage/:ecosystem', to: 'usage#ecosystem', as: :ecosystem_usage
  get 'usage/:ecosystem/:name', to: 'usage#show', as: :usage, constraints: { name: /.*/ }

  resources :hosts, constraints: { id: /.*/ }, only: [:index, :show], :defaults => {:format => :html} do
    resources :repositories, constraints: { id: /.*/ }, only: [:index, :show]
    resources :owners, only:[:show] do
      member do
        get '*subgroup', to: 'owners#subgroup', as: :subgroup, constraints: { subgroup: /.*/ }, format: :html
      end
    end
  end

  resources :exports, only: [:index], path: 'open-data'

  get '/404', to: 'errors#not_found'
  get '/422', to: 'errors#unprocessable'
  get '/500', to: 'errors#internal'

  root "home#index"
end
