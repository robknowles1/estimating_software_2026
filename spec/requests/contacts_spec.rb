require "rails_helper"

RSpec.describe "Contacts", type: :request do
  let(:user) { create(:user) }
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

    context "as turbo_stream from the proposal wizard (with estimate_id)" do
      let(:estimate) { create(:estimate, client: client) }
      let!(:proposal) { Proposals::BuildService.new(estimate: estimate).call }

      it "creates the contact and returns a turbo_stream that rebuilds the select with the new contact selected" do
        expect {
          post client_contacts_path(client),
            params: { contact: { first_name: "Jane", last_name: "Doe", email: "jane@example.com" }, estimate_id: estimate.id },
            as: :turbo_stream
        }.to change(Contact, :count).by(1)

        expect(response).to have_http_status(:ok)
        expect(response.media_type).to eq("text/vnd.turbo-stream.html")

        contact = Contact.order(:created_at).last
        expect(response.body).to include("proposal_contact_field")
        # The new contact appears in the rebuilt select, pre-selected.
        expect(response.body).to include("Jane Doe")
        expect(response.body).to match(/<option selected="selected" value="#{contact.id}">Jane Doe/)
      end

      it "does not mass-assign estimate_id onto the contact even when smuggled inside the contact hash" do
        expect {
          post client_contacts_path(client),
            params: {
              estimate_id: estimate.id,
              contact: { first_name: "Jane", last_name: "Doe", estimate_id: 999 }
            },
            as: :turbo_stream
        }.to change(Contact, :count).by(1)

        expect(response).to have_http_status(:ok)

        contact = Contact.last
        # The contact_params whitelist drops estimate_id, so it is never assigned
        # (the attribute does not even exist on the model).
        expect(contact.attributes).not_to have_key("estimate_id")
      end

      it "returns 422 turbo_stream with errors and creates no contact when first/last name are missing" do
        expect {
          post client_contacts_path(client),
            params: { contact: { first_name: "", last_name: "" }, estimate_id: estimate.id },
            as: :turbo_stream
        }.not_to change(Contact, :count)

        expect(response).to have_http_status(:unprocessable_content)
        expect(response.media_type).to eq("text/vnd.turbo-stream.html")
        expect(response.body).to include("add_contact_modal_frame")
        expect(response.body).to include("can&#39;t be blank").or include("can't be blank")
      end

      it "ignores an estimate_id that belongs to a different client" do
        other_estimate = create(:estimate)

        post client_contacts_path(client),
          params: { contact: { first_name: "Jane", last_name: "Doe" }, estimate_id: other_estimate.id },
          as: :turbo_stream

        # Contact is still created (it belongs to @client), but no wizard field is rebuilt.
        expect(Contact.where(client: client, first_name: "Jane").count).to eq(1)
        expect(response.body).not_to include("proposal_contact_field")
      end
    end
  end

  describe "POST /clients/:client_id/contacts with a role" do
    it "persists the role value" do
      post client_contacts_path(client), params: {
        contact: { first_name: "Jane", last_name: "Doe", role: "estimator" }
      }

      expect(response).to redirect_to(client_path(client))
      expect(Contact.last.role).to eq("estimator")
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

    it "succeeds when clearing a previously-set role (role is optional)" do
      contact = create(:contact, client: client, role: "estimator")

      patch client_contact_path(client, contact), params: {
        contact: { first_name: contact.first_name, last_name: contact.last_name, role: "" }
      }

      expect(response).to redirect_to(client_path(client))
      expect(contact.reload.role).to be_blank
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
