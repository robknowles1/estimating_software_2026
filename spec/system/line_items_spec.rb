require "rails_helper"

RSpec.describe "Line Items", type: :system do
  before { driven_by(:selenium_chrome_headless) }

  let!(:user) { create(:user) }
  let!(:client) { create(:client, company_name: "Test Millwork") }
  let!(:assembly_rate) { create(:labor_rate, labor_category: "assembly", hourly_rate: BigDecimal("25.00")) }

  def login
    visit new_session_path
    fill_in "Email", with: user.email
    fill_in "Password", with: "password123"
    click_button "Sign In"
    expect(page).to have_current_path(estimates_path, wait: 5)
  end

  describe "full core estimating loop" do
    # Create the estimate via factory to avoid headless-Chrome flakiness on multi-field
    # form submission when running in the full suite alongside other specs.
    let!(:estimate) { create(:estimate, client: client, created_by: user, title: "Core Loop Test") }

    it "configures PL1, adds section with quantity 5, adds material and labor line items, and sees correct subtotals" do
      login

      # Configure PL1 material slot
      pl1 = estimate.estimate_materials.find_by(category: "pl", slot_number: 1)
      visit edit_estimate_materials_path(estimate)
      fill_in "estimate_materials[#{pl1.id}][description]", with: "WD2 Maple"
      fill_in "estimate_materials[#{pl1.id}][price_per_unit]", with: "50.00"
      fill_in "estimate_materials[#{pl1.id}][unit]", with: "sheet"
      click_button "Save Material Costs"
      expect(page).to have_text("Material costs updated", wait: 5)
      pl1.reload
      expect(pl1.price_per_unit).to eq(BigDecimal("50.00"))

      # Add a section
      visit edit_estimate_path(estimate)
      fill_in "estimate_section[name]", with: "Base Two Door"
      fill_in "estimate_section[quantity]", with: "5"
      click_button "Add Section"
      expect(page).to have_text("Base Two Door", wait: 5)
      section = estimate.estimate_sections.reload.last

      # Add a material line item via the dedicated new page
      visit new_estimate_estimate_section_line_item_path(estimate, section)
      select "Material", from: "line_item[line_item_category]"
      select "Exterior", from: "line_item[component_type]"
      fill_in "Description", with: "Exterior Sheet Good"
      select "PL1", from: "line_item[estimate_material_id]"
      fill_in "line_item[component_quantity]", with: "0.32"
      click_button "Add Line Item"

      # Navigate away and back to confirm persistence
      visit edit_estimate_path(estimate)
      # Use page.body to bypass Capybara visible? check — descriptions are in truncate containers
      expect(page.body).to include("Exterior Sheet Good")

      # Add a labor line item
      visit new_estimate_estimate_section_line_item_path(estimate, section)
      select "Labor", from: "line_item[line_item_category]"
      select "Assembly", from: "line_item[labor_category]"
      fill_in "Description", with: "Assembly Labor"
      fill_in "line_item[hours_per_unit]", with: "0.375"
      click_button "Add Line Item"

      visit edit_estimate_path(estimate)
      expect(page.body).to include("Assembly Labor")

      # material: 0.32 × 5 × 50.00 = 80.00; labor: 0.375 × 5 × 25.00 = 46.875; total: ~126.88
      visit edit_estimate_path(estimate)
      expect(page).to have_text("$126.88", wait: 5)
    end
  end

  describe "adding an alternate line item" do
    let!(:estimate) { create(:estimate, client: client, created_by: user) }
    let!(:section) { create(:estimate_section, estimate: estimate, name: "Main Cabinets", quantity: 5) }
    let!(:material_item) do
      pl = estimate.estimate_materials.find_by(category: "pl", slot_number: 1)
      create(:line_item,
        estimate_section: section,
        line_item_category: "material",
        description: "Main material",
        estimate_material: pl,
        component_quantity: BigDecimal("1.0"))
    end
    let!(:alternate_item) do
      create(:line_item,
        estimate_section: section,
        line_item_category: "alternate",
        description: "Optional Crown Molding",
        freeform_quantity: BigDecimal("1"),
        unit_cost: BigDecimal("500.00"),
        markup_percent: BigDecimal("15.0"))
    end

    it "displays alternate item with Alternate category label on the estimate edit page" do
      login
      visit edit_estimate_path(estimate)

      # Alternate item should appear in the DOM (id: line_item_N)
      expect(page).to have_selector("#line_item_#{alternate_item.id}")
      # Description is in the DOM (may be clipped visually at narrow widths)
      expect(page.body).to include("Optional Crown Molding")
      # Category badge is visible
      expect(page).to have_text("Alternate")
      # The estimate totals section should show alternates separately
      expect(page).to have_text("Alternates")
    end

    it "does not include alternate items in the main non-burdened grand total" do
      login
      visit edit_estimate_path(estimate)

      # Main material: 1.0 × 5 × 0.00 (PL1 has no price) = 0
      # Alternate: excluded from grand total — only shows in Alternates section
      within("#totals_estimate_#{estimate.id}") do
        expect(page).to have_text("$0.00")
      end
    end
  end

  describe "job-level settings affect burdened total" do
    let!(:estimate) { create(:estimate, client: client, created_by: user) }
    let!(:section) { create(:estimate_section, estimate: estimate, name: "Cabinets", quantity: 1) }

    before do
      pl = estimate.estimate_materials.find_by(category: "pl", slot_number: 1)
      pl.update!(price_per_unit: BigDecimal("100.00"))
      create(:line_item,
        estimate_section: section,
        line_item_category: "material",
        description: "Test material",
        estimate_material: pl,
        component_quantity: BigDecimal("1.0"))
    end

    it "changes burdened total when profit_overhead_percent is set" do
      login
      visit edit_estimate_path(estimate)

      fill_in "estimate[profit_overhead_percent]", with: "20"
      fill_in "estimate[installer_crew_size]", with: "1"
      fill_in "estimate[delivery_crew_size]", with: "1"
      click_button "Save Job Settings"

      expect(page).to have_text("Estimate was successfully updated", wait: 5)
      # non-burdened = 100.00; burdened with 20% = 120.00
      expect(page).to have_text("$120.00")
    end
  end
end
