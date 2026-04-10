require "rails_helper"

RSpec.describe "Estimates", type: :system do
  before { driven_by(:selenium_chrome_headless) }

  let!(:user) { create(:user) }
  let!(:client) { create(:client, company_name: "Prestige Millwork") }

  def login(as: user, password: "password123")
    visit new_session_path
    fill_in "Email", with: as.email
    fill_in "Password", with: password
    click_button "Sign In"
    expect(page).to have_current_path(estimates_path, wait: 5)
  end

  describe "creating an estimate with sections and reordering" do
    it "creates an estimate, adds three sections, reorders them, and order persists after reload" do
      login

      visit new_estimate_path

      # Fill in the form
      select "Prestige Millwork", from: "estimate_client_id"
      fill_in "estimate[title]", with: "Full Kitchen Renovation"
      find("input[type='submit']").click

      expect(page).to have_current_path(%r{/estimates/\d+/edit}, wait: 5)
      expect(page).to have_text("Full Kitchen Renovation")

      # Add three sections by navigating to the new section form
      estimate_id = page.current_url.match(%r{/estimates/(\d+)})[1]

      visit new_estimate_estimate_section_path(estimate_id)
      fill_in "Name", with: "Cabinets"
      click_button "Create Estimate section"
      expect(page).to have_text("Cabinets")

      visit new_estimate_estimate_section_path(estimate_id)
      fill_in "Name", with: "Countertops"
      click_button "Create Estimate section"
      expect(page).to have_text("Countertops")

      visit new_estimate_estimate_section_path(estimate_id)
      fill_in "Name", with: "Trim Work"
      click_button "Create Estimate section"
      expect(page).to have_text("Trim Work")

      # Sections appear in creation order: Cabinets, Countertops, Trim Work
      # Find the Trim Work section by looking for the section container with that heading
      expect(page).to have_content("Trim Work")

      # Move "Trim Work" up once using its Move Up button
      trim_section = find("p.font-semibold", text: "Trim Work").ancestor("div.bg-white")
      within(trim_section) { find("button[title='Move Up']").click }

      # Reload and verify order persists
      page.driver.browser.navigate.refresh

      section_headings = all("p.font-semibold").map(&:text)
      trim_index = section_headings.index { |t| t.include?("Trim Work") }
      countertops_index = section_headings.index { |t| t.include?("Countertops") }
      expect(trim_index).to be < countertops_index
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
