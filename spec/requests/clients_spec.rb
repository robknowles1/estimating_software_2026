require "rails_helper"

RSpec.describe "Clients", type: :request do
  let(:user) { create(:user) }

  before { sign_in(user) }

  describe "GET /clients" do
    it "returns sorted list of clients" do
      create(:client, company_name: "Zeta Works")
      create(:client, company_name: "Alpha Millwork")

      get clients_path

      expect(response).to have_http_status(:ok)
      expect(response.body).to match(/Alpha Millwork.*Zeta Works/m)
    end

    it "shows empty state when no clients exist" do
      get clients_path

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("No clients yet")
    end

    it "redirects to login when not authenticated" do
      delete session_path
      get clients_path
      expect(response).to redirect_to(new_session_path)
    end
  end

  describe "GET /clients/:id" do
    it "renders the client detail page" do
      client = create(:client)
      get client_path(client)
      expect(response).to have_http_status(:ok)
      expect(response.body).to include(client.company_name)
    end
  end

  describe "POST /clients" do
    context "with valid params" do
      it "creates client and redirects to show" do
        expect {
          post clients_path, params: { client: { company_name: "New Corp" } }
        }.to change(Client, :count).by(1)

        expect(response).to redirect_to(client_path(Client.last))
      end
    end

    context "without company_name" do
      it "returns 422 and shows error" do
        expect {
          post clients_path, params: { client: { company_name: "" } }
        }.not_to change(Client, :count)

        expect(response).to have_http_status(:unprocessable_content)
        expect(response.body).to include("can&#39;t be blank").or include("can't be blank")
      end
    end
  end

  describe "PATCH /clients/:id" do
    it "updates client and redirects" do
      client = create(:client, company_name: "Old Name")

      patch client_path(client), params: { client: { company_name: "New Name" } }

      expect(response).to redirect_to(client_path(client))
      expect(client.reload.company_name).to eq("New Name")
    end
  end

  describe "DELETE /clients/:id" do
    context "with no associated estimates" do
      it "destroys client and contacts, redirects to index" do
        client = create(:client)
        create(:contact, client: client)

        expect {
          delete client_path(client)
        }.to change(Client, :count).by(-1).and change(Contact, :count).by(-1)

        expect(response).to redirect_to(clients_path)
      end
    end

    context "with existing estimates" do
      it "blocks deletion and keeps client record intact" do
        client = create(:client)
        create(:estimate, client: client)

        expect {
          delete client_path(client)
        }.not_to change(Client, :count)

        expect(response).to redirect_to(client_path(client))
        follow_redirect!
        expect(response.body).to include("Cannot delete")
      end
    end
  end
end
