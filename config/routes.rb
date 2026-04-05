Rails.application.routes.draw do
  resource :session, only: [ :new, :create, :destroy ]
  resources :users, only: [ :index, :new, :create, :edit, :update ]
  resources :estimates, only: [ :index ]
  resources :clients do
    resources :contacts, only: [ :new, :create, :edit, :update, :destroy ]
  end

  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  get "up" => "rails/health#show", as: :rails_health_check

  # Root redirects to estimates dashboard when logged in, login page otherwise
  root "estimates#index"
end
