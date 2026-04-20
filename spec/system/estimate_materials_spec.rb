require "rails_helper"

RSpec.describe "Estimate materials price book", type: :system do
  before { driven_by(:selenium_chrome_headless) }

  let!(:user)     { create(:user) }
  let!(:client)   { create(:client, company_name: "Prestige Millwork") }
  let!(:estimate) { create(:estimate, client: client, title: "Kitchen Job", created_by: user, tax_rate: BigDecimal("0.10"), tax_exempt: false) }

  def login
    visit new_session_path
    fill_in "Email", with: user.email
    fill_in "Password", with: "password123"
    click_button "Sign In"
    expect(page).to have_current_path(estimates_path, wait: 5)
  end

  describe "materials setup banner" do
    it "is visible on the estimate show page when no materials have been added" do
      login
      visit edit_estimate_path(estimate)
      expect(page).to have_text("Add materials before pricing products", wait: 3)
    end

    it "is not visible after at least one material has been added" do
      material = create(:material, default_price: BigDecimal("50.00"))
      create(:estimate_material, estimate: estimate, material: material)

      login
      visit edit_estimate_path(estimate)
      expect(page).not_to have_text("Add materials before pricing products")
    end
  end

  describe "adding a material from the library via search" do
    let!(:material) { create(:material, name: "Maple Plywood 3/4", default_price: BigDecimal("68.00")) }

    it "adds the material to the price book with the library default_price" do
      login
      visit new_estimate_estimate_material_path(estimate, mode: "search")

      fill_in "q", with: "Maple"
      click_button "Search"

      expect(page).to have_text("Maple Plywood 3/4", wait: 3)
      click_button "Add to Price Book"

      expect(page).to have_current_path(estimate_estimate_materials_path(estimate), wait: 5)
      expect(page).to have_text("Maple Plywood 3/4", wait: 3)
      expect(page).to have_text("68.0000", wait: 3)
    end
  end

  describe "editing the quote_price" do
    let!(:material) { create(:material, default_price: BigDecimal("68.00")) }
    let!(:em)       { create(:estimate_material, estimate: estimate, material: material, quote_price: BigDecimal("68.00")) }

    it "updates cost_with_tax to reflect new price * (1 + tax_rate)" do
      login
      visit estimate_estimate_materials_path(estimate)

      click_link "Edit", match: :first

      fill_in "estimate_material[quote_price]", with: "80.00"
      find("input[type='submit']").click

      expect(page).to have_current_path(estimate_estimate_materials_path(estimate), wait: 5)
      expect(page).to have_text("88.0000", wait: 3)
    end
  end
end
