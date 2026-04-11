require "rails_helper"

RSpec.describe "Catalog Items", type: :system do
  before { driven_by(:selenium_chrome_headless) }

  let!(:user) { create(:user) }
  let!(:client) { create(:client, company_name: "Test Millwork") }

  def login
    visit new_session_path
    fill_in "Email", with: user.email
    fill_in "Password", with: "password123"
    click_button "Sign In"
    expect(page).to have_current_path(estimates_path, wait: 5)
  end

  describe "catalog management" do
    it "allows a user to add, view, edit, and delete a catalog item" do
      login
      visit catalog_items_path

      # Empty state
      expect(page).to have_text("No catalog items yet")

      # Add an item
      click_link "Add Item"
      fill_in "Description", with: "Crown Moulding"
      fill_in "Default Unit", with: "LF"
      fill_in "Default Unit Cost", with: "8.50"
      fill_in "Category", with: "millwork"
      click_button "Add Item"

      expect(page).to have_text("Catalog item was successfully created.", wait: 5)
      expect(page).to have_text("Crown Moulding")

      # Edit the item
      click_link "Edit"
      fill_in "Default Unit Cost", with: "9.00"
      click_button "Update Item"

      expect(page).to have_text("Catalog item was successfully updated.", wait: 5)

      # Delete the item
      accept_confirm do
        click_button "Delete"
      end

      expect(page).to have_text("Catalog item was successfully deleted.", wait: 5)
      expect(page).to have_text("No catalog items yet")
    end
  end

  describe "line item description autocomplete" do
    let!(:crown_item) do
      create(:catalog_item,
        description: "Crown Moulding",
        default_unit: "LF",
        default_unit_cost: BigDecimal("8.50"),
        category: "millwork")
    end
    let!(:labor_rate) { create(:labor_rate, labor_category: "assembly", hourly_rate: BigDecimal("25.00")) }
    let!(:estimate) { create(:estimate, client: client, created_by: user, title: "Autocomplete Test") }
    let!(:section) { create(:estimate_section, estimate: estimate, name: "Cabinet Run", quantity: BigDecimal("1")) }

    it "shows a dropdown when the user types a matching description and pre-fills fields on selection" do
      login
      visit new_estimate_estimate_section_line_item_path(estimate, section)

      # Type enough characters to trigger autocomplete
      fill_in "Description", with: "Crown"

      # Wait for the dropdown to appear
      expect(page).to have_css("[role='listbox']", wait: 5)
      expect(page).to have_text("Crown Moulding", wait: 5)

      # Select the item from the dropdown
      find("[role='option']", text: "Crown Moulding").click

      # Description field should be filled (wait for Stimulus _select to update the value)
      expect(page).to have_field("Description", with: "Crown Moulding", wait: 5)
      # Unit field should be pre-filled
      expect(page).to have_field("line_item[unit]", with: "LF", wait: 5)
      # Unit cost field should be pre-filled
      expect(page).to have_field("line_item[unit_cost]", with: "8.5", wait: 5)

      # Fill remaining required fields and save
      fill_in "line_item[freeform_quantity]", with: "10"
      click_button "Add Line Item"

      expect(page).to have_text("Line item was successfully added.", wait: 5)

      # Verify persisted values
      line_item = section.line_items.reload.last
      expect(line_item.description).to eq("Crown Moulding")
      expect(line_item.unit).to eq("LF")
      expect(line_item.unit_cost.to_f).to be_within(0.01).of(8.50)
      expect(line_item.catalog_item_id).to eq(crown_item.id)
    end

    it "allows saving a fully custom description with no catalog match" do
      login
      visit new_estimate_estimate_section_line_item_path(estimate, section)

      fill_in "Description", with: "zzzzz custom item"

      # No dropdown should appear
      expect(page).not_to have_css("[role='option']", wait: 2)

      fill_in "line_item[freeform_quantity]", with: "5"
      fill_in "line_item[unit_cost]", with: "20.00"
      click_button "Add Line Item"

      expect(page).to have_text("Line item was successfully added.", wait: 5)

      line_item = section.line_items.reload.last
      expect(line_item.description).to eq("zzzzz custom item")
      expect(line_item.catalog_item_id).to be_nil
    end
  end
end
