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
    it "creates an estimate, redirects to materials price book, and shows all material slots" do
      login

      visit new_estimate_path
      select "Prestige Millwork", from: "estimate_client_id"
      fill_in "estimate[title]", with: "Full Kitchen Renovation"
      find("input[type='submit']").click

      # After create, redirected to materials edit (materials-first flow)
      expect(page).to have_current_path(%r{/estimates/\d+/materials/edit}, wait: 5)

      # All material slots should be visible
      expect(page).to have_text("PL1")
      # Categories rendered uppercase via CSS — use case-insensitive match
      expect(page).to have_text("Sheet Goods", normalize_ws: true, wait: 3).or have_text("SHEET GOODS", wait: 3)
      expect(page).to have_text("Hardware", normalize_ws: true, wait: 3).or have_text("HARDWARE", wait: 3)
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

  describe "entering quote prices in the materials price book" do
    it "saves quote prices and displays updated cost_with_tax on the page" do
      login

      visit new_estimate_path
      select "Prestige Millwork", from: "estimate_client_id"
      fill_in "estimate[title]", with: "Bathroom Vanities"
      find("input[type='submit']").click

      expect(page).to have_current_path(%r{/estimates/\d+/materials/edit}, wait: 5)

      # Enter a price for the PL1 slot
      estimate_id = page.current_url.match(%r{/estimates/(\d+)})[1]
      material = Material.find_by!(estimate_id: estimate_id, slot_key: "PL1")

      fill_in "materials[#{material.id}][quote_price]", with: "100.00"
      click_button "Save Material Costs"

      expect(page).to have_current_path(%r{/estimates/\d+/materials/edit}, wait: 5)

      # With 8% default tax rate: cost_with_tax = 100.00 * 1.08 = $108.00
      expect(page).to have_text("$108.00")
    end
  end

  describe "materials banner on estimate edit page" do
    it "shows the materials banner when no prices are set, hides after any price is set" do
      login

      visit new_estimate_path
      select "Prestige Millwork", from: "estimate_client_id"
      fill_in "estimate[title]", with: "Cabinet Project"
      find("input[type='submit']").click

      # Wait for redirect to materials edit
      expect(page).to have_current_path(%r{/estimates/\d+/materials/edit}, wait: 5)

      # Extract estimate_id from materials edit URL
      materials_url = page.current_path
      estimate_id   = materials_url.match(%r{/estimates/(\d+)/materials/edit})[1]

      # Navigate to estimate edit — banner should be visible
      visit edit_estimate_path(estimate_id)
      expect(page).to have_text("Set up materials", wait: 3)

      # Enter a price and return to estimate edit
      visit edit_estimate_materials_path(estimate_id)
      material = Material.find_by!(estimate_id: estimate_id, slot_key: "PL1")
      fill_in "materials[#{material.id}][quote_price]", with: "50.00"
      click_button "Save Material Costs"

      visit edit_estimate_path(estimate_id)
      expect(page).not_to have_text("Set up materials", wait: 3)
    end
  end

  describe "changing estimate status and filtering on dashboard" do
    it "changes status to sent and the estimate appears in sent filter" do
      estimate = create(:estimate, :skip_material_seeding, client: client, title: "Status Test Job", created_by: user, status: "draft")

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
      create(:estimate, :skip_material_seeding, client: client, title: "Draft Only Job", created_by: user, status: "draft")

      login
      visit estimates_path

      select "Sent", from: "status"
      click_button "Filter"

      expect(page).not_to have_text("Draft Only Job")
    end
  end
end
