require "rails_helper"

RSpec.describe "Contacts", type: :request do
  let(:user)   { create(:user) }
  let(:client) { create(:client) }

  before { sign_in(user) }

  describe "POST /clients/:client_id/contacts" do
    context "with valid params" do
      it "creates contact and redirects to client" do
        expect {
          post client_contacts_path(client), params: {
            contact: { first_name: "Jane", last_name: "Doe", email: "jane@example.com" }
          }
        }.to change(Contact, :count).by(1)

        expect(response).to redirect_to(client_path(client))
      end

      it "contact appears on client detail page" do
        post client_contacts_path(client), params: {
          contact: { first_name: "Jane", last_name: "Doe" }
        }

        follow_redirect!
        expect(response.body).to include("Jane")
        expect(response.body).to include("Doe")
      end
    end

    context "without required fields" do
      it "returns 422 and shows error" do
        expect {
          post client_contacts_path(client), params: {
            contact: { first_name: "", last_name: "" }
          }
        }.not_to change(Contact, :count)

        expect(response).to have_http_status(:unprocessable_content)
      end
    end
  end

  describe "PATCH /clients/:client_id/contacts/:id" do
    it "updates contact and redirects to client" do
      contact = create(:contact, client: client, first_name: "Old")

      patch client_contact_path(client, contact), params: {
        contact: { first_name: "Updated", last_name: contact.last_name }
      }

      expect(response).to redirect_to(client_path(client))
      expect(contact.reload.first_name).to eq("Updated")
    end
  end

  describe "DELETE /clients/:client_id/contacts/:id" do
    it "destroys the contact and redirects to client" do
      contact = create(:contact, client: client)

      expect {
        delete client_contact_path(client, contact)
      }.to change(Contact, :count).by(-1)

      expect(response).to redirect_to(client_path(client))
    end
  end
end
