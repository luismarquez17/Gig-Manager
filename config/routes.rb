Rails.application.routes.draw do
  devise_for :users, controllers: { registrations: 'users/registrations' }
  
  root "pages#dashboard"

  # Superadmin Namespace
  namespace :superadmin do
    get '/', to: 'dashboard#index', as: :dashboard
    resources :companies do
      member do
        patch :toggle_status
        post :regenerate_token
        post :switch_tenant
      end
    end
    resources :subscription_payments, only: [:index] do
      member do
        post :approve
        post :reject
      end
    end
    post '/switch_tenant', to: 'companies#switch_tenant', as: :switch_tenant_global
  end

  # Link de unión / onboarding de empresas
  get '/join/:slug', to: 'onboarding#show', as: :join_company
  post '/join/:slug', to: 'onboarding#process_join', as: :process_join_company


  resources :shopping_items do
    member do
      patch :toggle_purchased
      get   :add_to_inventory
      post  :increment_inventory
    end
  end

  get '/availability', to: 'pages#availability', as: 'availability_dashboard'
  get '/financials', to: 'pages#financials', as: 'financials_dashboard'
  get '/normativas', to: 'pages#normativas', as: 'normativas'
  get '/suspended', to: 'pages#suspended', as: 'suspended_company'

  # Gestión de Suscripciones y Stripe
  resources :subscriptions, only: [:index] do
    collection do
      post :checkout
      post :portal
      post :report_payment
    end
  end
  post '/stripe_webhooks', to: 'stripe_webhooks#create'


  get '/funds/:fund_type', to: 'funds#show', as: 'fund'

  resources :clients do
    collection do
      get :debts
    end
    member do
      post :merge
    end
  end
  resources :gig_payments, only: [:index, :edit, :update, :destroy]
  
  namespace :client do
    resources :gigs, only: [:index, :show] do
      member do
        post :request_upsell
      end
    end
  end

  # Portal Público de Clientes (Acceso mediante token seguro de WhatsApp)
  get '/portal/:token', to: 'portals#show', as: 'public_portal'
  get '/portal/:token/worker/:worker_id', to: 'portals#worker_profile', as: 'public_portal_worker'
  post '/portal/:token/sign', to: 'portals#sign_contract', as: 'sign_public_portal_contract'
  post '/portal/:token/request_upsell', to: 'portals#request_upsell', as: 'request_public_portal_upsell'

  # Presupuestos de Clientes
  resources :client_quotes
  get '/q/:token', to: 'client_quotes#public_show', as: 'public_client_quote'
  post '/q/:token/submit', to: 'client_quotes#public_submit', as: 'submit_public_client_quote'

  resources :gig_upsell_requests, only: [] do
    member do
      post :approve
      post :reject
    end
  end

  resources :gigs, only: [:index, :new, :create, :destroy, :show, :edit, :update] do
    member do
      get :load_in_checklist
      post :add_kit
      post :assign_staff
      delete :remove_staff
      patch :update_staff_pay
      get :print_contract
      post :add_upsell
    end
    resources :gig_timeline_items, only: [:create, :destroy]
    resources :gig_items, only: [:create, :destroy]
    resources :gig_payments, only: [:index, :new, :create]
    resources :fund_allocations, only: [:create, :destroy]
    resources :fund_allocations, only: [] do
      resources :fund_expenses, only: [:create, :destroy]
    end
  end
  resources :gig_items, only: [] do
    member do
      patch :toggle
      post :report_damage
      patch :update_quantities
      post :report_lost
    end
  end

  resources :items do
    member do
      post :report_damage
    end
    resources :inventory_items, only: [:update]
  end
  resources :categories, only: [:create, :destroy]
  resources :sub_categories, only: [:create, :destroy]
  resources :maintenance_records, only: [:index, :new, :create, :edit, :update]

  get '/investments/report', to: 'investments#report', as: 'investments_report'
  resources :investments

  resources :standard_upsells

  resources :preset_budgets do
    member do
      get :print
    end
  end

  resources :kits do
    member do
      post :add_item
      delete 'remove_item/:item_id', to: 'kits#remove_item', as: 'remove_item'
    end
  end
  resources :users, only: [:index, :edit, :update, :show] do
    member do
      patch :update_role
    end
  end
  resources :employee_payments, only: [:index, :new, :create, :edit, :update, :destroy] do
    collection do
      get :new_worker_report
      post :create_worker_report
      post :reset_balance
    end
    member do
      post :approve
      post :reject
    end
  end
  # Staff: view only their assigned gigs
  get '/my_gigs', to: 'gigs#my', as: 'my_gigs'
  # Staff & Musician: view their payments and balances
  get '/my_payments', to: 'pages#my_payments', as: 'my_payments'
  get '/help', to: 'pages#help', as: 'help'

  resources :notifications, only: [:index, :create, :destroy] do
    member do
      post :mark_as_read
    end
    collection do
      post :mark_all_as_read
    end
  end
end