module Authentication
  extend ActiveSupport::Concern

  included do
    before_action :require_login
    helper_method :current_user, :logged_in?
  end

  private

  def current_user
    @current_user ||= User.find_by(id: session[:user_id]) if session[:user_id]
  end

  def logged_in?
    current_user.present?
  end

  def require_login
    unless logged_in?
      redirect_to new_session_path, alert: "Please log in to continue."
    end
  end
end
