Rails.application.routes.draw do
  resource :session, only: [ :new, :create, :destroy ]
  resources :users, only: [ :index, :new, :create, :edit, :update ]
  resources :estimates do
    resource :materials, module: :estimates, only: [ :edit, :update ]
    resources :estimate_sections do
      member { patch :move }
      resources :line_items do
        member { patch :move }
      end
    end
  end
  resources :clients do
    resources :contacts, only: [ :new, :create, :edit, :update, :destroy ]
  end
  resources :catalog_items do
    collection { get :search }
  end

  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  get "up" => "rails/health#show", as: :rails_health_check

  # Root redirects to estimates dashboard when logged in, login page otherwise
  root "estimates#index"
end
