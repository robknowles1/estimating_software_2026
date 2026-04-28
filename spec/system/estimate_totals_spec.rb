require "rails_helper"

RSpec.describe "Estimate totals panel", type: :system do
  include ActionView::Helpers::NumberHelper
  include ActionView::RecordIdentifier

  before { driven_by(:selenium_chrome_headless) }

  let!(:user)   { create(:user) }
  let!(:client) { create(:client) }
  let!(:estimate) do
    create(:estimate, client: client, created_by: user,
           profit_overhead_percent: 0, pm_supervision_percent: 0,
           tax_rate: 0, tax_exempt: false,
           installer_crew_size: 2, delivery_qty: 0, delivery_rate: 400,
           install_travel_qty: 0, per_diem_qty: 0, hotel_qty: 0, airfare_qty: 0,
           countertop_quote: 0)
  end
  let!(:material) { create(:material, default_price: BigDecimal("200.00")) }
  let!(:estimate_material) do
    create(:estimate_material, estimate: estimate, material: material,
           quote_price: BigDecimal("200.00"))
  end
  let!(:line_item) do
    create(:line_item, estimate: estimate,
           exterior_material_id: estimate_material.id,
           exterior_qty: 1.0,
           quantity: 1)
  end

  before do
    %w[detail mill assembly customs finish install].each do |cat|
      LaborRate.find_or_create_by!(labor_category: cat) do |lr|
        lr.hourly_rate = BigDecimal("20.00")
      end
    end
  end

  def login
    visit new_session_path
    fill_in "Email", with: user.email
    fill_in "Password", with: "password123"
    click_button "Sign In"
    expect(page).to have_current_path(estimates_path, wait: 5)
  end

  def totals
    EstimateTotalsCalculator.new(estimate.reload).call
  end

  describe "Test 1 — no sticky inline style (AC-1)" do
    it "totals container has no inline style attribute with sticky or fixed" do
      login
      visit edit_estimate_path(estimate)

      totals_id = "estimate_#{estimate.id}_totals"
      expect(page).to have_css("##{totals_id}", wait: 5)

      expect(page).not_to have_css("[id^='estimate_'][id$='_totals'][style*='sticky']")
      expect(page).not_to have_css("[id^='estimate_'][id$='_totals'][style*='fixed']")
    end
  end

  describe "Test 2 — per-line-item subtotal on card (AC-3)" do
    it "shows the non_burdened_total as currency within the line item card" do
      login
      visit edit_estimate_path(estimate)

      result     = totals
      expected   = number_to_currency(result.line_item_results[line_item.id][:non_burdened_total])

      within "##{dom_id(line_item)}" do
        expect(page).to have_text(expected, wait: 5)
      end
    end
  end

  describe "Test 3 — breakdown collapsed on load (AC-6)" do
    it "does not show COGS Breakdown text when page first loads" do
      login
      visit edit_estimate_path(estimate)

      # h3 uses uppercase CSS class so Selenium innerText returns all-caps
      expect(page).not_to have_text("COGS BREAKDOWN", wait: 5)
    end
  end

  describe "Test 4 — clicking summary expands breakdown (AC-7)" do
    it "reveals COGS Breakdown after clicking the summary toggle" do
      login
      visit edit_estimate_path(estimate)

      find("summary").click

      # h3 uses uppercase CSS class so Selenium innerText returns all-caps
      expect(page).to have_text("COGS BREAKDOWN", wait: 5)
    end
  end

  describe "Test 5 — clicking summary again collapses breakdown (AC-8)" do
    it "hides COGS Breakdown after toggling open then closed" do
      login
      visit edit_estimate_path(estimate)

      find("summary").click
      # h3 uses uppercase CSS class so Selenium innerText returns all-caps
      expect(page).to have_text("COGS BREAKDOWN", wait: 5)

      find("summary").click
      expect(page).not_to have_text("COGS BREAKDOWN", wait: 5)
    end
  end

  describe "Test 6 — headline totals always visible (AC-9)" do
    it "shows burdened total on page load without user interaction" do
      login
      visit edit_estimate_path(estimate)

      result   = totals
      expected = number_to_currency(result.burdened_total)

      expect(page).to have_text(expected, wait: 5)
    end
  end
end
