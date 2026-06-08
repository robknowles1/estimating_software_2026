Rails.application.routes.draw do
  resource  :session,  only: [ :new, :create, :destroy ]
  resources :users,    only: [ :index, :new, :create, :edit, :update ]
  resources :products
  resources :materials
  resources :material_sets do
    resources :material_set_items, only: [ :create, :destroy ]
    member do
      post :apply_to_estimate
    end
  end
  resources :estimates do
    resources :line_items, only: [ :new, :create, :edit, :update, :destroy ] do
      collection do
        post :import
        post :apply_aliases
      end
      member do
        patch :move
      end
    end
    resources :estimate_materials, only: [ :index, :new, :create, :edit, :update, :destroy ] do
      collection do
        post :inline_create
      end
    end
    resource :proposal, only: [ :new, :create, :show ] do
      scope module: :proposals do
        get  "steps/:step", to: "steps#show",   as: :step
        patch "steps/:step", to: "steps#update"
      end
    end
  end
  resources :clients do
    resources :contacts, only: [ :new, :create, :edit, :update, :destroy ]
  end

  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  get "up" => "rails/health#show", as: :rails_health_check

  # Root redirects to estimates dashboard when logged in, login page otherwise
  root "estimates#index"
end
