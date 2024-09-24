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

      resources :topics, only: [:index, :show], constraints: { id: /.*/ }

      get 'usage', to: 'usage#index', as: :usage_index
      get 'usage/:ecosystem', to: 'usage#ecosystem', as: :ecosystem_usage
      get 'usage/:ecosystem/:name/dependencies', to: 'dependencies#index', as: :usage_dependencies, constraints: { name: /.*/ }
      get 'usage/:ecosystem/:name/dependent_repositories', to: 'usage#dependent_repositories', as: :usage_dependent_repositories, constraints: { name: /.*/ }, defaults: { format: :json }
      get 'usage/:ecosystem/:name/ping', to: 'usage#ping', as: :ping_usage, constraints: { name: /.*/ }, defaults: { format: :json }
      get 'usage/:ecosystem/:name', to: 'usage#show', as: :usage, constraints: { name: /.*/ }, defaults: { format: :json }

      get 'repositories/lookup', to: 'repositories#lookup', as: :repositories_lookup
      resources :hosts, constraints: { id: /.*/ }, defaults: { format: :json }, only: [:index, :show] do
        resources :owners, only:[:index, :show] do
          collection do
            get :lookup
          end
          member do
            get :repositories
            get :ping
          end
        end
        resources :repositories, constraints: { id: /.*/ }, defaults: { format: :json }, only: [:index, :show] do
          resources :tags do
            resources :manifests, only: [:index]
          end
          resources :releases
          resources :manifests, only: [:index]
          member do
            get :ping
          end
        end

        resources :topics, only: [:index, :show], constraints: { id: /.*/ }
        
        member do
          get :repository_names, to: 'repositories#names', as: :repository_names
        end
      end

      resources :package_names do
        collection do
          get :docker
          get :actions
          get :swiftpm
          get :carthage
          get :meteor
        end
      end
    end
  end

  get '/usage', to: 'usage#index', as: :usage_index
  get 'usage/:ecosystem', to: 'usage#ecosystem', as: :ecosystem_usage
  get 'usage/:ecosystem/:name', to: 'usage#show', as: :usage, constraints: { name: /.*/ }, defaults: { format: :html }

  resources :hosts, constraints: { id: /.*/ }, only: [:index, :show], :defaults => {:format => :html} do
    resources :repositories, constraints: { id: /.*/ }, only: [:index, :show] do
      member do
        get :funding
        get :dependencies
        get :readme
      end
    end
    resources :owners, only:[:index, :show] do
      member do
        get '*subgroup', to: 'owners#subgroup', as: :subgroup, constraints: { subgroup: /.*/ }, format: :html
      end
    end
    member do
      get :topics
      get "topics/:topic", to: 'hosts#topic', as: :topic
    end

    collection do
      get 'kinds/:id', to: 'hosts#kind', as: :kind
    end
  end

  resources :topics, only: [:index, :show], constraints: { id: /.*/ }, defaults: { format: :html }

  resources :exports, only: [:index], path: 'open-data'

  get '/404', to: 'errors#not_found'
  get '/422', to: 'errors#unprocessable'
  get '/500', to: 'errors#internal'

  root "home#index"
end
