require "rails_helper"

RSpec.describe "Line Items", type: :system do
  before { driven_by(:selenium_chrome_headless) }

  let!(:user)     { create(:user) }
  let!(:client)   { create(:client, company_name: "Prestige Millwork") }
  let!(:estimate) { create(:estimate, client: client, title: "Kitchen Remodel", created_by: user) }

  def login(as: user, password: "password123")
    visit new_session_path
    fill_in "Email", with: as.email
    fill_in "Password", with: password
    click_button "Sign In"
    expect(page).to have_current_path(estimates_path, wait: 5)
  end

  describe "adding a line item via product dropdown" do
    it "shows 'Based on' annotation on the line item card" do
      product = create(:product, name: "MDF Base 2-door", category: "Base Cabinets", unit: "EA")

      login
      visit new_estimate_line_item_path(estimate)

      select "MDF Base 2-door", from: "line_item[product_id]"
      fill_in "line_item[description]", with: "MDF Base 2-door"
      fill_in "line_item[quantity]", with: "1"
      find("input[type='submit']").click

      expect(page).to have_current_path(edit_estimate_path(estimate), wait: 5)
      expect(page).to have_text("Based on: MDF Base 2-door", wait: 3)
    end
  end

  describe "adding a freeform line item" do
    it "saves without a 'Based on' annotation and product_id is nil" do
      login
      visit new_estimate_line_item_path(estimate)

      fill_in "line_item[description]", with: "Custom Freeform Cabinet"
      fill_in "line_item[quantity]", with: "2"
      find("input[type='submit']").click

      expect(page).to have_current_path(edit_estimate_path(estimate), wait: 5)
      expect(page).to have_text("Custom Freeform Cabinet", wait: 3)
      expect(page).not_to have_text("Based on:")

      line_item = estimate.line_items.find_by!(description: "Custom Freeform Cabinet")
      expect(line_item.product_id).to be_nil
    end
  end

  describe "overriding a pre-filled description after selecting a product" do
    it "saves the overridden description, not the product name" do
      product = create(:product, name: "MDF Base 2-door", category: "Base Cabinets", unit: "EA")

      login
      visit new_estimate_line_item_path(estimate)

      select "MDF Base 2-door", from: "line_item[product_id]"
      fill_in "line_item[description]", with: "Custom Override Description"
      fill_in "line_item[quantity]", with: "1"
      find("input[type='submit']").click

      expect(page).to have_current_path(edit_estimate_path(estimate), wait: 5)
      expect(page).to have_text("Custom Override Description", wait: 3)

      line_item = estimate.line_items.find_by!(description: "Custom Override Description")
      expect(line_item.description).to eq("Custom Override Description")
    end
  end

  describe "applying a product sets _qty fields but leaves _material_id nil" do
    it "sets exterior_qty via apply_to and exterior_material_id stays nil" do
      product = create(:product, name: "MDF Base 2-door", category: "Base Cabinets", unit: "EA",
                       exterior_qty: BigDecimal("2.0"))
      login
      visit new_estimate_line_item_path(estimate)

      select "MDF Base 2-door", from: "line_item[product_id]"
      fill_in "line_item[description]", with: "Test Cabinet"
      fill_in "line_item[quantity]", with: "1"

      # Wait for JS to prefill fields (product_selector_controller#fill)
      expect(page).to have_field("line_item[exterior_qty]", with: "2.0", wait: 3)

      find("input[type='submit']").click

      expect(page).to have_current_path(edit_estimate_path(estimate), wait: 5)

      li = estimate.line_items.find_by!(description: "Test Cabinet")
      expect(li.exterior_qty).to eq(BigDecimal("2.0"))
      expect(li.exterior_material_id).to be_nil
    end
  end

  describe "formula input on Qty field" do
    let!(:line_item) do
      create(:line_item, estimate: estimate, description: "Formula Test Cabinet", quantity: 1)
    end

    def wait_for_js
      expect(page).to have_css("html[data-js-ready='true']", wait: 5)
    end

    def edit_qty_and_blur(value, expected_value: value)
      wait_for_js
      qty_field = find_field("line_item[quantity]")
      qty_field.click
      qty_field.fill_in(with: value)
      execute_script("document.querySelector('[name=\"line_item[quantity]\"]').blur()")
      expect(page).to have_field("line_item[quantity]", with: expected_value)
    end

    before { login }

    it "evaluates a division formula (6/28) to 4 decimal places" do
      visit edit_estimate_line_item_path(estimate, line_item)
      edit_qty_and_blur("6/28", expected_value: "0.2143")
      expect(find_field("line_item[quantity]").value).to eq("0.2143")
    end

    it "evaluates a compound formula ((12+4)/8) to its decimal result" do
      visit edit_estimate_line_item_path(estimate, line_item)
      edit_qty_and_blur("(12+4)/8", expected_value: "2")
      expect(find_field("line_item[quantity]").value).to eq("2")
    end

    it "passes through a plain integer unchanged" do
      visit edit_estimate_line_item_path(estimate, line_item)
      edit_qty_and_blur("2")
      value = find_field("line_item[quantity]").value
      expect(value).to eq("2").or eq("2.0")
    end

    it "leaves the field unchanged when the value contains non-whitelist characters" do
      visit edit_estimate_line_item_path(estimate, line_item)
      edit_qty_and_blur("abc")
      expect(find_field("line_item[quantity]").value).to eq("abc")
    end

    it "leaves the field unchanged when the result is negative (-2)" do
      visit edit_estimate_line_item_path(estimate, line_item)
      edit_qty_and_blur("-2")
      expect(find_field("line_item[quantity]").value).to eq("-2")
    end

    it "leaves the field unchanged when the result is zero (5-5)" do
      visit edit_estimate_line_item_path(estimate, line_item)
      edit_qty_and_blur("5-5")
      expect(find_field("line_item[quantity]").value).to eq("5-5")
    end

    it "leaves the field unchanged when the value contains a JS comment token (6//28)" do
      visit edit_estimate_line_item_path(estimate, line_item)
      edit_qty_and_blur("6//28")
      expect(find_field("line_item[quantity]").value).to eq("6//28")
    end

    it "leaves the field unchanged when the value uses the JS exponentiation operator (2**3)" do
      visit edit_estimate_line_item_path(estimate, line_item)
      edit_qty_and_blur("2**3")
      expect(find_field("line_item[quantity]").value).to eq("2**3")
    end

    it "leaves the field unchanged when the result rounds to zero at 4dp (1/100000)" do
      visit edit_estimate_line_item_path(estimate, line_item)
      edit_qty_and_blur("1/100000")
      expect(find_field("line_item[quantity]").value).to eq("1/100000")
    end

    it "saves the evaluated decimal when the form is submitted after entering a formula" do
      visit edit_estimate_line_item_path(estimate, line_item)
      edit_qty_and_blur("6/28", expected_value: "0.2143")
      expect(find_field("line_item[quantity]").value).to eq("0.2143")
      find("input[type='submit']").click
      expect(page).to have_current_path(edit_estimate_path(estimate), wait: 5)
      line_item.reload
      expect(line_item.quantity).to eq(BigDecimal("0.2143"))
    end
  end
end
