Rails.application.routes.draw do
  devise_for :users
  
  root "pages#dashboard"
  get '/availability', to: 'pages#availability', as: 'availability_dashboard'
  get '/financials', to: 'pages#financials', as: 'financials_dashboard'

  get '/funds/:fund_type', to: 'funds#show', as: 'fund'

  resources :clients
  resources :gig_payments, only: [:index]
  resources :gigs, only: [:index, :new, :create, :destroy, :show] do
    member do
      get :load_in_checklist
      post :add_kit
      post :assign_staff
    end
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
    resources :inventory_items, only: [:update]
  end
  resources :maintenance_records, only: [:index, :edit, :update]

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
  resources :users, only: [:index] do
    member do
      patch :update_role
    end
  end
  resources :employee_payments, only: [:index, :new, :create]
  # Staff: view only their assigned gigs
  get '/my_gigs', to: 'gigs#my', as: 'my_gigs'
  get '/help', to: 'pages#help', as: 'help'
end