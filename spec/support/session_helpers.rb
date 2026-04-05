module SessionHelpers
  def sign_in(user)
    post session_path, params: { email: user.email, password: "password123" }
  end
end

RSpec.configure do |config|
  config.include SessionHelpers, type: :request
end
