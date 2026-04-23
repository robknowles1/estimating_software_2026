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

  describe "estimate edit page" do
    it "shows the 'Add Product' button" do
      estimate = create(:estimate, client: client, title: "Cabinet Project", created_by: user)
      login
      visit edit_estimate_path(estimate)

      expect(page).to have_text("Add Product", wait: 3)
    end
  end

  describe "job settings — pm_supervision_percent updates totals via Turbo Stream" do
    it "stays on edit page and updates totals panel without full reload" do
      estimate = create(:estimate, client: client, title: "PM Supervision Test", created_by: user,
                        profit_overhead_percent: 0, pm_supervision_percent: 0,
                        tax_rate: 0, tax_exempt: false,
                        installer_crew_size: 2, delivery_qty: 0, delivery_rate: 400,
                        install_travel_qty: 0, per_diem_qty: 0, hotel_qty: 0, airfare_qty: 0,
                        countertop_quote: 0)
      material = create(:material, default_price: BigDecimal("100.00"))
      em = create(:estimate_material, estimate: estimate, material: material, quote_price: BigDecimal("100.00"))
      create(:line_item, estimate: estimate,
             exterior_material_id: em.id,
             exterior_qty: 1.0,
             quantity: 1)
      create(:labor_rate, labor_category: "detail",   hourly_rate: BigDecimal("20.00")) unless LaborRate.exists?(labor_category: "detail")
      create(:labor_rate, labor_category: "mill",     hourly_rate: BigDecimal("22.00")) unless LaborRate.exists?(labor_category: "mill")
      create(:labor_rate, labor_category: "assembly", hourly_rate: BigDecimal("25.00")) unless LaborRate.exists?(labor_category: "assembly")
      create(:labor_rate, labor_category: "customs",  hourly_rate: BigDecimal("18.00")) unless LaborRate.exists?(labor_category: "customs")
      create(:labor_rate, labor_category: "finish",   hourly_rate: BigDecimal("21.00")) unless LaborRate.exists?(labor_category: "finish")
      create(:labor_rate, labor_category: "install",  hourly_rate: BigDecimal("23.00")) unless LaborRate.exists?(labor_category: "install")

      login
      visit edit_estimate_path(estimate)

      # Fill in pm_supervision_percent in Job Settings
      within(".col-span-1") do
        find("input[name='estimate[pm_supervision_percent]']").set("10")
        find("input[name='estimate[pm_supervision_percent]']").ancestor("form").find("input[type='submit']").click
      end

      # Assert page does NOT navigate away (Turbo Stream response, not redirect)
      expect(page).to have_current_path(edit_estimate_path(estimate), wait: 5)

      # Assert totals panel is present with the estimate id
      expect(page).to have_css("#estimate_#{estimate.id}_totals", wait: 5)

      # burdened_total with pm_supervision_percent=10, grand_non_burdened=100:
      # burden_multiplier = 1.0 * 1.10 = 1.10
      # burdened_total = 100 * 1.10 + 0 = 110.00
      expect(page).to have_css("#estimate_#{estimate.id}_totals", text: "$110.00", wait: 5)
    end
  end

  describe "job settings — tax_exempt propagates to material cost_with_tax" do
    it "sets cost_with_tax equal to quote_price when tax_exempt is checked" do
      client_with_tax = create(:client, company_name: "Taxable Corp", tax_exempt: false)
      estimate = create(:estimate, client: client_with_tax, title: "Tax Exempt Test", created_by: user,
                        tax_rate: BigDecimal("0.10"), tax_exempt: false,
                        profit_overhead_percent: 0, pm_supervision_percent: 0,
                        installer_crew_size: 2, delivery_qty: 0, delivery_rate: 400,
                        install_travel_qty: 0, per_diem_qty: 0, hotel_qty: 0, airfare_qty: 0,
                        countertop_quote: 0)
      material = create(:material, default_price: BigDecimal("100.00"))
      create(:estimate_material, estimate: estimate, material: material, quote_price: BigDecimal("100.00"))

      login
      visit edit_estimate_path(estimate)

      # Check the tax_exempt checkbox in Job Settings, submit
      within(".col-span-1") do
        check "estimate[tax_exempt]"
        find("input[name='estimate[tax_exempt]']").ancestor("form").find("input[type='submit']").click
      end

      # After Turbo Stream response, visit price book to verify cost_with_tax
      visit estimate_estimate_materials_path(estimate)

      # cost_with_tax should equal quote_price (100.0000) when tax_exempt
      expect(page).to have_text("100.0000", wait: 5)
      # The cost_with_tax column should show 100.0000 (not 110.0000)
      expect(page).not_to have_text("110.0000")
    end
  end

  describe "job costs — delivery updates burdened total" do
    it "shows correct burdened_total after entering delivery_qty and delivery_rate" do
      create(:labor_rate, labor_category: "detail",   hourly_rate: BigDecimal("20.00")) unless LaborRate.exists?(labor_category: "detail")
      create(:labor_rate, labor_category: "mill",     hourly_rate: BigDecimal("22.00")) unless LaborRate.exists?(labor_category: "mill")
      create(:labor_rate, labor_category: "assembly", hourly_rate: BigDecimal("25.00")) unless LaborRate.exists?(labor_category: "assembly")
      create(:labor_rate, labor_category: "customs",  hourly_rate: BigDecimal("18.00")) unless LaborRate.exists?(labor_category: "customs")
      create(:labor_rate, labor_category: "finish",   hourly_rate: BigDecimal("21.00")) unless LaborRate.exists?(labor_category: "finish")
      create(:labor_rate, labor_category: "install",  hourly_rate: BigDecimal("23.00")) unless LaborRate.exists?(labor_category: "install")

      # Estimate with no overhead/pm, tax 0 — so burdened_total = materials_cost + delivery_cost
      estimate = create(:estimate, client: client, title: "Delivery Totals Test", created_by: user,
                        profit_overhead_percent: 0, pm_supervision_percent: 0,
                        tax_rate: 0, tax_exempt: false,
                        installer_crew_size: 2, delivery_qty: 0, delivery_rate: 400,
                        install_travel_qty: 0, per_diem_qty: 0, hotel_qty: 0, airfare_qty: 0,
                        countertop_quote: 0)
      material = create(:material, default_price: BigDecimal("100.00"))
      em = create(:estimate_material, estimate: estimate, material: material, quote_price: BigDecimal("100.00"))
      create(:line_item, estimate: estimate,
             exterior_material_id: em.id,
             exterior_qty: 1.0,
             quantity: 1)

      login
      visit edit_estimate_path(estimate)

      # Fill in delivery_qty: 2 and delivery_rate: 400 in Job Costs form
      within(".col-span-1") do
        find("input[name='estimate[delivery_qty]']").set("2")
        find("input[name='estimate[delivery_rate]']").set("400")
        # Submit the Job Costs form (first form with a submit inside col-span-1 that has delivery fields)
        find("input[name='estimate[delivery_qty]']").ancestor("form").find("input[type='submit']").click
      end

      # Assert totals panel shows correct burdened_total
      # grand_non_burdened = 100 (1 unit * $100 material)
      # burden_multiplier = 1.0 (0% overhead, 0% pm)
      # delivery_cost = 2 * 400 = 800
      # burdened_total = 100 * 1.0 + 800 = 900.00
      expect(page).to have_css("#estimate_#{estimate.id}_totals", text: "$900.00", wait: 5)
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
