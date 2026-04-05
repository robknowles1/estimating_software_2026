class SessionsController < ApplicationController
  skip_before_action :require_login, only: [ :new, :create ]
  layout "sessions"

  def new
  end

  def create
    user = User.find_by(email: params[:email].to_s.downcase)

    if user&.authenticate(params[:password])
      reset_session                      # prevent session fixation
      session[:user_id] = user.id
      redirect_to estimates_path, notice: "Signed in successfully."
    else
      flash.now[:alert] = "Invalid email or password."
      render :new, status: :unprocessable_content
    end
  end

  def destroy
    reset_session                        # clear all session data, not just user_id
    redirect_to new_session_path, notice: "Signed out."
  end
end
