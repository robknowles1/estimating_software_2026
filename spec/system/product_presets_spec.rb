require "rails_helper"

RSpec.describe "Product Presets Auto-Population", type: :system do
  before { driven_by(:selenium_chrome_headless) }

  def login(user)
    visit new_session_path
    fill_in "Email", with: user.email
    fill_in "Password", with: "password123"
    click_button "Sign In"
    expect(page).to have_current_path(estimates_path, wait: 5)
  end

  def wait_for_js
    expect(page).to have_css("html[data-js-ready='true']", wait: 5)
  end

  def type_into_tom_select(input, text)
    page.execute_script("arguments[0].focus()", input.native)
    input.send_keys(text)
    if input.value.to_s.empty?
      page.execute_script(
        "var el = arguments[0]; el.value = arguments[1]; " \
        "el.dispatchEvent(new Event('input', { bubbles: true }));",
        input.native, text
      )
    end
  end

  def click_tom_select_option(option)
    page.driver.browser.action.move_to(option.native).click.perform
  end

  def pick_product(text)
    product_combobox = find("select[name='line_item[product_id]']", visible: false)
    product_control = product_combobox.find(:xpath, "following-sibling::*[contains(@class,'ts-wrapper')][1]/*[contains(@class,'ts-control')]")
    product_control.click
    type_into_tom_select(product_control.find("input"), text)
    option = find(".ts-dropdown-content [role='option']", text: text, match: :prefer_exact, wait: 3)
    click_tom_select_option(option)
  end

  # Scenario 1: Slot code entry and persistence
  describe "Scenario 1: Slot code entry and persistence" do
    it "shows the Material Slot Codes section, saves a slot code, and displays it on the index" do
      # Arrange
      user    = create(:user)
      product = create(:product, name: "Base Cabinet 1-Door", unit: "EA")
      login(user)

      # Act — visit product edit, fill in a slot code, and save
      visit edit_product_path(product)
      expect(page).to have_text("Material Slot Codes")
      fill_in "product[pulls_slot_code]", with: "PULL1"
      find("input[type='submit']").click

      # Assert — redirected to index, PULL1 appears as a slot code pill
      expect(page).to have_current_path(products_path, wait: 5)
      expect(page).to have_text("PULL1", wait: 3)
    end
  end

  # Scenario 2: Auto-population on line item create
  describe "Scenario 2: Auto-population on line item create" do
    it "assigns pulls_material_id from the price book when product slot code matches" do
      # Arrange
      user     = create(:user)
      client   = create(:client, company_name: "Millwork Co")
      estimate = create(:estimate, client: client, title: "Kitchen Job", created_by: user,
                                   tax_rate: BigDecimal("0"), tax_exempt: false)
      material = create(:material, name: "Satin Nickel Pull", default_price: BigDecimal("4.50"))
      em       = create(:estimate_material, estimate: estimate, material: material,
                                            quote_price: BigDecimal("4.50"), short_code: "PULL1")
      product  = create(:product, name: "Base 1-Door", category: "Base", unit: "EA",
                                  pulls_slot_code: "PULL1")
      login(user)

      # Act — create a new line item using the product.
      # We set the product_id via JS to avoid Tom Select timing issues in headless Chrome
      # when estimate_materials are present (material-slot comboboxes add initialization load).
      visit new_estimate_line_item_path(estimate)
      wait_for_js

      # Select product by directly setting the Tom Select value — avoids typing-then-click
      # race conditions that can occur when multiple Tom Select instances are initializing.
      page.execute_script(<<~JS, product.id.to_s)
        var sel = document.querySelector("select[name='line_item[product_id]']");
        var ts = sel.tomselect;
        if (ts) { ts.setValue(arguments[0]); }
      JS
      # Wait for the product-selector JS to auto-fill the description
      expect(page).to have_field("line_item[description]", with: "Base 1-Door", wait: 3)
      find_field("line_item[quantity]").set("1")
      page.execute_script("document.querySelector('input[type=\"submit\"]').click()")

      # Assert — line item is saved with pulls_material_id resolved from price book
      expect(page).to have_current_path(edit_estimate_path(estimate), wait: 5)
      li = estimate.line_items.reload.last
      expect(li.pulls_material_id).to eq(em.id)
    end
  end

  # Scenario 3: Graceful degradation — no price book match
  describe "Scenario 3: Graceful degradation — no price book match" do
    it "creates line item without error when the price book has no short codes" do
      # Arrange
      user     = create(:user)
      client   = create(:client, company_name: "Millwork Co")
      estimate = create(:estimate, client: client, title: "Empty PB Job", created_by: user,
                                   tax_rate: BigDecimal("0"), tax_exempt: false)
      product  = create(:product, name: "Base 2-Door", category: "Base", unit: "EA",
                                  pulls_slot_code: "PULL1", hinges_slot_code: "HINGE1")
      login(user)

      # Act — create a line item (no price book entries at all)
      visit new_estimate_line_item_path(estimate)
      wait_for_js

      page.execute_script(<<~JS, product.id.to_s)
        var sel = document.querySelector("select[name='line_item[product_id]']");
        var ts = sel.tomselect;
        if (ts) { ts.setValue(arguments[0]); }
      JS
      expect(page).to have_field("line_item[description]", with: "Base 2-Door", wait: 3)
      find_field("line_item[quantity]").set("2")
      page.execute_script("document.querySelector('input[type=\"submit\"]').click()")

      # Assert — line item is created, page redirected, no error shown
      expect(page).to have_current_path(edit_estimate_path(estimate), wait: 5)
      expect(page).not_to have_css(".alert", wait: 1)

      li = estimate.line_items.reload.last
      expect(li.pulls_material_id).to be_nil
      expect(li.hinges_material_id).to be_nil
    end
  end
end
