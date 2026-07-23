Rails.application.routes.draw do
  devise_for :users
  
  root "pages#dashboard"

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

  get '/funds/:fund_type', to: 'funds#show', as: 'fund'

  resources :clients do
    member do
      post :merge
    end
  end
  resources :gig_payments, only: [:index, :edit, :update, :destroy]
  
  namespace :client do
    resources :gigs, only: [:index, :show]
  end

  # Portal Público de Clientes (Acceso mediante token seguro de WhatsApp)
  get '/portal/:token', to: 'portals#show', as: 'public_portal'
  get '/portal/:token/worker/:worker_id', to: 'portals#worker_profile', as: 'public_portal_worker'
  post '/portal/:token/sign', to: 'portals#sign_contract', as: 'sign_public_portal_contract'

  resources :gigs, only: [:index, :new, :create, :destroy, :show, :edit, :update] do
    member do
      get :load_in_checklist
      post :add_kit
      post :assign_staff
      get :print_contract
    end
    resources :gig_timeline_items, only: [:create, :destroy]
    resources :gig_items, only: [:create, :destroy]
    resources :gig_payments, only: [:index, :new, :create]
    resources :fund_allocations, only: [:create, :destroy]
    resources :fund_allocations, only: [] do
      resources :fund_expenses, only: [:create, :destroy]
    end
  end
  
  patch '/gig_items/:id/toggle', to: 'gig_items#toggle', as: 'toggle_gig_item'
  post '/gig_items/:id/report_damage', to: 'gig_items#report_damage', as: 'report_damage_gig_item'
  patch '/gig_items/:id/update_quantities', to: 'gig_items#update_quantities', as: 'update_quantities_gig_item'
  post '/gig_items/:id/report_lost', to: 'gig_items#report_lost', as: 'report_lost_gig_item'

  resources :items do
    member do
      post :report_damage
    end
    resources :inventory_items, only: [:update]
  end
  resources :categories, only: [:create, :destroy]
  resources :maintenance_records, only: [:index, :new, :create, :edit, :update]

  get '/investments/report', to: 'investments#report', as: 'investments_report'
  resources :investments

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
  resources :employee_payments, only: [:index, :new, :create, :edit, :update, :destroy]
  # Staff: view only their assigned gigs
  get '/my_gigs', to: 'gigs#my', as: 'my_gigs'
  # Staff & Musician: view their payments and balances
  get '/my_payments', to: 'pages#my_payments', as: 'my_payments'
  get '/help', to: 'pages#help', as: 'help'
end