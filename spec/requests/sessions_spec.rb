require 'rails_helper'

RSpec.describe "Sessions", type: :request do
  let!(:user) { create(:user, email: "test@example.com", password: "password123", password_confirmation: "password123") }

  describe "POST /session" do
    context "with valid credentials" do
      it "redirects to estimates dashboard and sets session" do
        post session_path, params: { email: "test@example.com", password: "password123" }
        expect(response).to redirect_to(estimates_path)
        follow_redirect!
        expect(response).to have_http_status(:ok)
      end
    end

    context "with invalid password" do
      it "returns unprocessable entity and does not create session" do
        post session_path, params: { email: "test@example.com", password: "wrong_password" }
        expect(response).to have_http_status(:unprocessable_content)
      end
    end

    context "with unknown email" do
      it "returns unprocessable entity and does not create session" do
        post session_path, params: { email: "nobody@example.com", password: "password123" }
        expect(response).to have_http_status(:unprocessable_content)
      end
    end
  end

  describe "DELETE /session" do
    before { sign_in(user) }

    it "destroys session and redirects to login page" do
      delete session_path
      expect(response).to redirect_to(new_session_path)
    end
  end
end
