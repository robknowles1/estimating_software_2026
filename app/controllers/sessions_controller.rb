class SessionsController < ApplicationController
  skip_before_action :require_login, only: [ :new, :create ]
  layout "sessions"

  def new
  end

  def create
    user = User.find_by(email: params[:email].to_s.downcase)

    if user&.authenticate(params[:password])
      session[:user_id] = user.id
      redirect_to estimates_path, notice: "Signed in successfully."
    else
      flash.now[:alert] = "Invalid email or password."
      render :new, status: :unprocessable_content
    end
  end

  def destroy
    session.delete(:user_id)
    redirect_to new_session_path, notice: "Signed out."
  end
end
