require 'rails_helper'

RSpec.describe "Users", type: :request do
  let!(:current_user) { create(:user) }

  before { sign_in(current_user) }

  describe "POST /users" do
    context "with valid params" do
      let(:valid_params) do
        { user: { name: "Jane Doe", email: "jane@example.com", password: "secret123", password_confirmation: "secret123" } }
      end

      it "creates a new user and redirects to user list" do
        expect {
          post users_path, params: valid_params
        }.to change(User, :count).by(1)

        expect(response).to redirect_to(users_path)
      end
    end

    context "with a duplicate email" do
      let!(:existing) { create(:user, email: "taken@example.com") }
      let(:duplicate_params) do
        { user: { name: "Other Person", email: "taken@example.com", password: "secret123", password_confirmation: "secret123" } }
      end

      it "returns unprocessable entity and shows error" do
        post users_path, params: duplicate_params
        expect(response).to have_http_status(:unprocessable_content)
        expect(response.body).to include("Email")
      end
    end

    context "with missing name" do
      let(:missing_name_params) do
        { user: { name: "", email: "new@example.com", password: "secret123", password_confirmation: "secret123" } }
      end

      it "returns unprocessable entity" do
        post users_path, params: missing_name_params
        expect(response).to have_http_status(:unprocessable_content)
      end
    end

    context "with missing email" do
      let(:missing_email_params) do
        { user: { name: "Someone", email: "", password: "secret123", password_confirmation: "secret123" } }
      end

      it "returns unprocessable entity" do
        post users_path, params: missing_email_params
        expect(response).to have_http_status(:unprocessable_content)
      end
    end
  end
end
