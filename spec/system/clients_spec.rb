require "rails_helper"

RSpec.describe "Client and Contact Management", type: :system do
  before { driven_by(:selenium_chrome_headless) }

  let!(:user) { create(:user) }

  def login(as: user, password: "password123")
    visit new_session_path
    fill_in "Email", with: as.email
    fill_in "Password", with: password
    click_button "Sign In"
    expect(page).to have_current_path(estimates_path)
  end

  describe "primary contact management" do
    it "marking second contact as primary clears the first contact's primary flag" do
      client = create(:client, company_name: "Prestige Cabinets")
      alice  = create(:contact, client: client, first_name: "Alice", last_name: "Smith", is_primary: true)
      bob    = create(:contact, client: client, first_name: "Bob",   last_name: "Jones", is_primary: false)

      login

      # Edit Bob via the UI and mark him as primary
      visit edit_client_contact_path(client, bob)
      find("input[type=checkbox][id='contact_is_primary']").click
      click_button "Update Contact"

      # Bob is now primary, Alice is not
      within("table tbody") do
        expect(find("tr", text: "Bob Jones")).to have_text("Primary")
        expect(find("tr", text: "Alice Smith")).not_to have_text("Primary")
      end
    end
  end

  describe "blocked client deletion" do
    it "shows block message and preserves client when estimates exist" do
      login

      client = create(:client, company_name: "Locked Client Co")
      create(:estimate, client: client)

      visit client_path(client)
      expect(page).to have_text("Locked Client Co")

      accept_confirm do
        click_button "Delete"
      end

      expect(page).to have_current_path(client_path(client))
      expect(page).to have_text("Cannot delete")
      expect(Client.find_by(id: client.id)).to be_present
    end

    it "deletes client successfully when no estimates exist" do
      login

      client = create(:client, company_name: "Removable Client Co")

      visit client_path(client)
      expect(page).to have_text("Removable Client Co")

      accept_confirm do
        click_button "Delete"
      end

      expect(page).to have_current_path(clients_path)
      expect(page).not_to have_text("Removable Client Co")
    end
  end
end
