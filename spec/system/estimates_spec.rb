require "rails_helper"

RSpec.describe "Estimates", type: :system do
  before { driven_by(:selenium_chrome_headless) }

  let!(:user)   { create(:user) }
  let!(:client) { create(:client, company_name: "Prestige Millwork") }

  def login(as: user, password: "password123")
    visit new_session_path
    fill_in "Email", with: as.email
    fill_in "Password", with: password
    click_button "Sign In"
    expect(page).to have_current_path(estimates_path, wait: 5)
  end

  describe "creating a new estimate" do
    it "creates an estimate and redirects to the estimate edit page" do
      login

      visit new_estimate_path
      select "Prestige Millwork", from: "estimate_client_id"
      fill_in "estimate[title]", with: "Full Kitchen Renovation"
      find("input[type='submit']").click

      # After create, redirected to estimate edit (no materials-first flow)
      expect(page).to have_current_path(%r{/estimates/\d+/edit}, wait: 5)
      expect(page).to have_text("Full Kitchen Renovation", wait: 3)
    end

    it "shows estimate number in EST-YYYY-NNNN format in the top bar" do
      login

      visit new_estimate_path
      select "Prestige Millwork", from: "estimate_client_id"
      fill_in "estimate[title]", with: "Office Build-Out"
      find("input[type='submit']").click

      expect(page).to have_text(/EST-\d{4}-\d{4}/, wait: 5)
    end
  end

  describe "estimate edit page — materials elements removed" do
    it "does not show a Materials button" do
      estimate = create(:estimate, client: client, title: "Cabinet Project", created_by: user)
      login
      visit edit_estimate_path(estimate)

      expect(page).not_to have_text("Materials")
      expect(page).not_to have_text("Set up materials")
    end

    it "does not show a materials setup banner" do
      estimate = create(:estimate, client: client, title: "Cabinet Project", created_by: user)
      login
      visit edit_estimate_path(estimate)

      expect(page).not_to have_text("Material costs aren't set up yet")
    end

    it "shows the 'Add Product' button" do
      estimate = create(:estimate, client: client, title: "Cabinet Project", created_by: user)
      login
      visit edit_estimate_path(estimate)

      expect(page).to have_text("Add Product", wait: 3)
    end
  end

  describe "changing estimate status and filtering on dashboard" do
    it "changes status to sent and the estimate appears in sent filter" do
      estimate = create(:estimate, client: client, title: "Status Test Job", created_by: user, status: "draft")

      login
      visit edit_estimate_path(estimate)

      select "Sent", from: "Status"
      click_button "Update Status"

      expect(page).to have_text("Estimate was successfully updated")

      visit estimates_path
      select "Sent", from: "status"
      click_button "Filter"

      expect(page).to have_text("Status Test Job")
    end

    it "does not show draft estimate when filtering by sent" do
      create(:estimate, client: client, title: "Draft Only Job", created_by: user, status: "draft")

      login
      visit estimates_path

      select "Sent", from: "status"
      click_button "Filter"

      expect(page).not_to have_text("Draft Only Job")
    end
  end
end
