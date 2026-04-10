require "rails_helper"

RSpec.describe "Client and Contact Management", type: :system do
  before { driven_by(:selenium_chrome_headless) }

  let!(:user) { create(:user) }

  def login(as: user, password: "password123")
    visit new_session_path
    fill_in "Email", with: as.email
    fill_in "Password", with: password
    click_button "Sign In"
    expect(page).to have_current_path(estimates_path, wait: 5)
  end

  describe "primary contact badge" do
    it "shows Primary badge only on the primary contact" do
      client = create(:client, company_name: "Prestige Cabinets")
      create(:contact, client: client, first_name: "Alice", last_name: "Smith", is_primary: false)
      create(:contact, client: client, first_name: "Bob",   last_name: "Jones", is_primary: true)

      login
      visit client_path(client)

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
