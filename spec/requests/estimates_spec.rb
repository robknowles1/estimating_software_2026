require "rails_helper"

RSpec.describe "Estimates", type: :request do
  let(:user) { create(:user) }
  let(:client) { create(:client) }

  before { sign_in(user) }

  describe "GET /estimates" do
    it "returns http ok" do
      get estimates_path
      expect(response).to have_http_status(:ok)
    end

    it "shows all estimates with client name, title, status, and number" do
      estimate = create(:estimate, client: client, title: "Kitchen Remodel")
      get estimates_path
      expect(response.body).to include(estimate.estimate_number)
      expect(response.body).to include(estimate.title)
      expect(response.body).to include(client.company_name)
    end

    it "shows empty state when no estimates exist" do
      get estimates_path
      expect(response.body).to include("No estimates yet")
    end

    it "redirects to login when not authenticated" do
      delete session_path
      get estimates_path
      expect(response).to redirect_to(new_session_path)
    end

    context "with status filter" do
      let!(:draft_estimate) { create(:estimate, client: client, title: "Draft Job", status: "draft") }
      let!(:sent_estimate)  { create(:estimate, client: client, title: "Sent Job", status: "sent") }

      it "returns only estimates with the given status" do
        get estimates_path, params: { status: "sent" }
        expect(response.body).to include("Sent Job")
        expect(response.body).not_to include("Draft Job")
      end

      it "returns all estimates when no status filter" do
        get estimates_path
        expect(response.body).to include("Draft Job")
        expect(response.body).to include("Sent Job")
      end
    end

    context "with search query" do
      let!(:matching)     { create(:estimate, client: client, title: "Kitchen Remodel") }
      let!(:nonmatching)  { create(:estimate, client: client, title: "Garage Door") }

      it "returns only matching estimates" do
        get estimates_path, params: { q: "Kitchen" }
        expect(response.body).to include("Kitchen Remodel")
        expect(response.body).not_to include("Garage Door")
      end
    end
  end

  describe "GET /estimates/new" do
    it "renders the new estimate form" do
      get new_estimate_path
      expect(response).to have_http_status(:ok)
    end
  end

  describe "POST /estimates" do
    let(:valid_params) do
      { estimate: { client_id: client.id, title: "New Kitchen" } }
    end

    context "with valid params" do
      it "creates estimate and redirects to edit" do
        expect {
          post estimates_path, params: valid_params
        }.to change(Estimate, :count).by(1)

        expect(response).to redirect_to(edit_estimate_path(Estimate.last))
      end

      it "sets status to draft" do
        post estimates_path, params: valid_params
        expect(Estimate.last.status).to eq("draft")
      end

      it "generates an estimate number in EST-YYYY-NNNN format" do
        post estimates_path, params: valid_params
        expect(Estimate.last.estimate_number).to match(/\AEST-\d{4}-\d{4}\z/)
      end

      it "sets created_by to current user" do
        post estimates_path, params: valid_params
        expect(Estimate.last.created_by_user_id).to eq(user.id)
      end
    end

    context "without client_id" do
      it "returns unprocessable entity" do
        post estimates_path, params: { estimate: { title: "No Client" } }
        expect(response).to have_http_status(:unprocessable_content)
      end

      it "does not create an estimate" do
        expect {
          post estimates_path, params: { estimate: { title: "No Client" } }
        }.not_to change(Estimate, :count)
      end
    end

    context "without title" do
      it "returns unprocessable entity" do
        post estimates_path, params: { estimate: { client_id: client.id } }
        expect(response).to have_http_status(:unprocessable_content)
      end

      it "does not create an estimate" do
        expect {
          post estimates_path, params: { estimate: { client_id: client.id } }
        }.not_to change(Estimate, :count)
      end
    end
  end

  describe "GET /estimates/:id/edit" do
    let(:estimate) { create(:estimate, client: client) }

    it "renders the edit page" do
      get edit_estimate_path(estimate)
      expect(response).to have_http_status(:ok)
      expect(response.body).to include(estimate.title)
    end
  end

  describe "PATCH /estimates/:id" do
    let(:estimate) { create(:estimate, client: client, status: "draft") }

    it "updates the estimate status and redirects" do
      patch estimate_path(estimate), params: { estimate: { status: "sent", title: estimate.title, client_id: client.id } }
      expect(response).to redirect_to(edit_estimate_path(estimate))
      expect(estimate.reload.status).to eq("sent")
    end

    it "updates the estimate title" do
      patch estimate_path(estimate), params: { estimate: { title: "Updated Title", client_id: client.id } }
      expect(estimate.reload.title).to eq("Updated Title")
    end
  end

  describe "DELETE /estimates/:id" do
    let!(:estimate) { create(:estimate, client: client) }

    it "destroys the estimate and redirects to index" do
      expect {
        delete estimate_path(estimate)
      }.to change(Estimate, :count).by(-1)

      expect(response).to redirect_to(estimates_path)
    end
  end
end
