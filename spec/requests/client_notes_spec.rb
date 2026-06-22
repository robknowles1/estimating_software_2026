require "rails_helper"

RSpec.describe "ClientNotes", type: :request do
  let(:user) { create(:user) }
  let(:client) { create(:client) }

  describe "POST /clients/:client_id/client_notes" do
    context "authenticated" do
      before { sign_in(user) }

      it "creates the note and redirects to the client" do
        expect {
          post client_client_notes_path(client), params: {
            client_note: { body: "Called Blake re: bid deadline" }
          }
        }.to change(client.client_notes, :count).by(1)

        expect(response).to redirect_to(client_path(client))
        expect(client.client_notes.last.body).to eq("Called Blake re: bid deadline")
      end

      it "returns 422 and creates no note when the body is blank" do
        contact  = create(:contact, client: client, first_name: "Pat", last_name: "Smith")
        estimate = create(:estimate, client: client, title: "Big Remodel")

        expect {
          post client_client_notes_path(client), params: {
            client_note: { body: "" }
          }
        }.not_to change(ClientNote, :count)

        expect(response).to have_http_status(:unprocessable_content)

        # The whole clients/show page must re-render with every panel intact,
        # not a bare error fragment.
        expect(response.body).to include(I18n.t("clients.show.contacts_heading"))
        expect(response.body).to include("Pat Smith")
        expect(response.body).to include(I18n.t("clients.show.estimates_heading"))
        expect(response.body).to include(estimate.title)
        expect(response.body).to include(estimate.estimate_number)
      end
    end

    context "unauthenticated" do
      it "redirects to login and creates no note" do
        expect {
          post client_client_notes_path(client), params: {
            client_note: { body: "Sneaky note" }
          }
        }.not_to change(ClientNote, :count)

        expect(response).to redirect_to(new_session_path)
      end
    end
  end

  describe "DELETE /clients/:client_id/client_notes/:id" do
    context "authenticated" do
      before { sign_in(user) }

      it "destroys the note and redirects to the client" do
        note = create(:client_note, client: client)

        expect {
          delete client_client_note_path(client, note)
        }.to change(ClientNote, :count).by(-1)

        expect(response).to redirect_to(client_path(client))
      end

      it "returns 404 when the note belongs to a different client" do
        other_client = create(:client)
        note = create(:client_note, client: other_client)

        expect {
          delete client_client_note_path(client, note)
        }.not_to change(ClientNote, :count)

        expect(response).to have_http_status(:not_found)
      end
    end

    context "unauthenticated" do
      it "redirects to login and destroys no note" do
        note = create(:client_note, client: client)

        expect {
          delete client_client_note_path(client, note)
        }.not_to change(ClientNote, :count)

        expect(response).to redirect_to(new_session_path)
      end
    end
  end
end
