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

  def wait_for_js
    expect(page).to have_css("html[data-js-ready='true']", wait: 5)
  end

  # Picks a product from the Tom Select-enhanced product combobox by typing
  # `text` into the visible search input and clicking the matching dropdown
  # option.  The original native <select> is hidden by Tom Select, so
  # Capybara's `select` helper cannot operate on it.
  def pick_product(text)
    product_combobox = find("select[name='line_item[product_id]']", visible: false)
    product_control = product_combobox.find(:xpath, "following-sibling::*[contains(@class,'ts-wrapper')][1]/*[contains(@class,'ts-control')]")
    product_control.click
    type_into_tom_select(product_control.find("input"), text)
    # Use `[role=option]` to skip the optgroup heading which is also rendered
    # under .ts-dropdown-content but is not selectable.
    option = find(".ts-dropdown-content [role='option']", text: text, match: :prefer_exact, wait: 3)
    click_tom_select_option(option)
  end

  # Picks a material for a slot via Tom Select.  Slot is e.g. :exterior or :other.
  def pick_material(slot, text)
    input = open_material_slot(slot)
    type_into_tom_select(input, text)
    option = find(".ts-dropdown-content [role='option']", text: text, match: :prefer_exact, wait: 3)
    click_tom_select_option(option)
  end

  # Tom Select listens to mousedown on options, but Capybara's `.click` does
  # not always deliver a mousedown event that Tom Select recognises (the
  # bubbling stops at the option element before its mousedown handler runs).
  # Driving the click through Selenium's mouse action chain produces a real
  # mouse-move + mousedown + click sequence that Tom Select handles.
  def click_tom_select_option(option)
    page.driver.browser.action.move_to(option.native).click.perform
  end

  # send_keys can drop characters when focus has been disrupted by an earlier
  # Tom Select interaction in the same browser session.  Force focus first and
  # then use Selenium's keyboard action to deliver the keystrokes — this gives
  # TomSelect a real key sequence (which it needs in order to register the
  # query and update its `searchResults` cache for option clicks).
  def type_into_tom_select(input, text)
    page.execute_script("arguments[0].focus()", input.native)
    input.send_keys(text)
    # If the input.value did not update (a known intermittent Selenium issue
    # under headless Chrome when focus is lost mid-test), fall back to a
    # JS-driven input event so the test still exercises the filter path.
    if input.value.to_s.empty?
      page.execute_script(
        "var el = arguments[0]; el.value = arguments[1]; " \
        "el.dispatchEvent(new Event('input', { bubbles: true }));",
        input.native, text
      )
    end
  end

  def open_material_slot(slot)
    select_el = find("select[name='line_item[#{slot}_material_id]']", visible: false)
    wrapper = select_el.find(:xpath, "following-sibling::*[contains(@class,'ts-wrapper')][1]")
    scroll_to(wrapper, align: :center)
    control = wrapper.find(".ts-control")
    control.click
    input = wrapper.find(".ts-control input")
    # In some test orderings the click leaves focus unset on the input which
    # causes send_keys to drop characters; force-focus to be safe.
    page.execute_script("arguments[0].focus()", input.native)
    input
  end

  describe "adding a line item via product dropdown" do
    it "shows 'Based on' annotation on the line item card" do
      product = create(:product, name: "MDF Base 2-door", category: "Base Cabinets", unit: "EA")

      login
      visit new_estimate_line_item_path(estimate)
      wait_for_js

      pick_product("MDF Base 2-door")
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
      wait_for_js

      desc_field = find_field("line_item[description]")
      desc_field.set("Custom Freeform Cabinet")
      qty_field = find_field("line_item[quantity]")
      qty_field.set("2")

      # Verify the values stuck before submitting — under certain headless
      # Chrome focus states from a previous spec, fill_in can be no-op'd.
      expect(desc_field.value).to eq("Custom Freeform Cabinet")

      # Dispatch the click via JS — a bare `.click()` on the submit button is
      # occasionally swallowed by headless Chrome after a previous spec has
      # driven Selenium's action chain on a Tom Select dropdown option.
      page.execute_script("document.querySelector('input[type=\"submit\"]').click()")

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
      wait_for_js

      pick_product("MDF Base 2-door")
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
      wait_for_js

      pick_product("MDF Base 2-door")
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

    def edit_qty_and_blur(value, expected_value: value, field: "line_item[quantity]")
      wait_for_js
      qty_field = find_field(field)
      qty_field.click
      qty_field.fill_in(with: value)
      execute_script("document.querySelector('[name=\"#{field}\"]').blur()")
      expect(page).to have_field(field, with: expected_value)
    end

    before { login }

    it "evaluates a division formula (6/28) to 2 decimal places" do
      visit edit_estimate_line_item_path(estimate, line_item)
      edit_qty_and_blur("6/28", expected_value: "0.21")
      expect(find_field("line_item[quantity]").value).to eq("0.21")
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

    it "leaves the field unchanged when the result rounds to zero at 2dp (1/100000)" do
      visit edit_estimate_line_item_path(estimate, line_item)
      edit_qty_and_blur("1/100000")
      expect(find_field("line_item[quantity]").value).to eq("1/100000")
    end

    it "saves the evaluated decimal when the form is submitted after entering a formula" do
      visit edit_estimate_line_item_path(estimate, line_item)
      edit_qty_and_blur("6/28", expected_value: "0.21")
      expect(find_field("line_item[quantity]").value).to eq("0.21")
      find("input[type='submit']").click
      expect(page).to have_current_path(edit_estimate_path(estimate), wait: 5)
      line_item.reload
      expect(line_item.quantity).to eq(BigDecimal("0.21"))
    end

    it "evaluates a division formula (12/24) to 0.5 on exterior_qty" do
      visit edit_estimate_line_item_path(estimate, line_item)
      edit_qty_and_blur("12/24", expected_value: "0.5", field: "line_item[exterior_qty]")
      expect(find_field("line_item[exterior_qty]").value).to eq("0.5")
    end

    it "passes through a plain integer unchanged on locks_qty" do
      visit edit_estimate_line_item_path(estimate, line_item)
      edit_qty_and_blur("2", field: "line_item[locks_qty]")
      value = find_field("line_item[locks_qty]").value
      expect(value).to eq("2").or eq("2.0")
    end
  end

  # SPEC-018: other material slot — select + qty → correct non_burdened_total on card
  describe "SPEC-018: other material slot calculates non_burdened_total" do
    # Use a zero-tax estimate so cost_with_tax == quote_price and math is simple.
    let!(:zero_tax_estimate) do
      create(:estimate, client: client, title: "Zero Tax Estimate", created_by: user,
                        tax_rate: BigDecimal("0"), tax_exempt: false)
    end
    let!(:material)     { create(:material, name: "Pine Sheet", default_price: BigDecimal("10.00")) }
    let!(:estimate_mat) { create(:estimate_material, estimate: zero_tax_estimate, material: material, quote_price: BigDecimal("10.00")) }
    let!(:line_item) do
      create(:line_item, estimate: zero_tax_estimate, description: "Other Slot Cabinet", quantity: 1)
    end

    it "selects an other material, enters qty 3, saves, and shows $30.00 on the card" do
      login
      visit edit_estimate_line_item_path(zero_tax_estimate, line_item)
      expect(page).to have_css("html[data-js-ready='true']", wait: 5)

      pick_material(:other, "Pine Sheet")
      fill_in "line_item[other_qty]", with: "3"

      find("input[type='submit']").click

      expect(page).to have_current_path(edit_estimate_path(zero_tax_estimate), wait: 5)

      within("#line_item_#{line_item.id}") do
        expect(page).to have_text("$30.00", wait: 3)
      end
    end
  end

  describe "Enter key on the line item form" do
    let!(:line_item) do
      create(:line_item, estimate: estimate, description: "Enter Key Cabinet", quantity: 1)
    end

    before { login }

    it "moves focus to the next field instead of submitting the form" do
      visit edit_estimate_line_item_path(estimate, line_item)
      expect(page).to have_css("html[data-js-ready='true']", wait: 5)

      qty = find_field("line_item[quantity]")
      qty.click
      qty.fill_in(with: "6/28")
      qty.send_keys(:enter)

      expect(page).to have_current_path(edit_estimate_line_item_path(estimate, line_item), wait: 3)
      # Tom Select hides the underlying <select> for exterior_material_id; tab_on_enter
      # skips invisible fields and lands on the next visible focusable: the Tom Select
      # search input belonging to the exterior slot wrapper.  The active element should
      # be an <input> inside the .ts-control of the exterior_material_id wrapper.
      expect(evaluate_script(<<~JS)).to be true
        (function () {
          var el = document.activeElement;
          if (!el) return false;
          var wrapper = el.closest('.ts-wrapper');
          if (!wrapper) return false;
          var sibling = wrapper.previousElementSibling;
          while (sibling && sibling.tagName !== 'SELECT') { sibling = sibling.previousElementSibling; }
          return sibling && sibling.name === 'line_item[exterior_material_id]';
        })()
      JS
      expect(page).to have_field("line_item[quantity]", with: "0.21", wait: 3)
    end

    it "still submits the form when Enter is pressed on a focused text field via the submit button default" do
      visit edit_estimate_line_item_path(estimate, line_item)
      expect(page).to have_css("html[data-js-ready='true']", wait: 5)

      execute_script("document.querySelector(\"input[type='submit']\").focus()")
      page.driver.browser.action.send_keys(:return).perform

      expect(page).to have_current_path(edit_estimate_path(estimate), wait: 5)
    end
  end

  # SPEC-019 scenarios A-D — Tom Select on product + material slots, plus inline create.
  describe "SPEC-019: Tom Select on product and material slot comboboxes" do
    let!(:zero_tax_estimate) do
      create(:estimate, client: client, title: "SPEC-019 Estimate", created_by: user,
                        tax_rate: BigDecimal("0"), tax_exempt: false)
    end

    # Scenario A — product combobox filters and the description auto-fills
    it "filters the product combobox by typing and fills the description on selection" do
      create(:product, name: "MDF Base 2-door", category: "Base Cabinets", unit: "EA")

      login
      visit new_estimate_line_item_path(zero_tax_estimate)
      wait_for_js

      pick_product("MDF Base 2-door")

      # product_selector_controller#fill should populate the description from the
      # native change event that Tom Select dispatches on item add.
      expect(page).to have_field("line_item[description]", with: "MDF Base 2-door", wait: 3)
    end

    # Scenario B — material slot combobox filters the price book client-side
    it "filters a material slot combobox by typing so only matches appear" do
      maple = create(:material, name: "Maple Plywood", default_price: BigDecimal("60.00"))
      birch = create(:material, name: "Birch Plywood", default_price: BigDecimal("55.00"))
      create(:estimate_material, estimate: zero_tax_estimate, material: maple, quote_price: BigDecimal("60.00"))
      create(:estimate_material, estimate: zero_tax_estimate, material: birch, quote_price: BigDecimal("55.00"))

      line_item = create(:line_item, estimate: zero_tax_estimate, description: "Filter Test", quantity: 1)

      login
      visit edit_estimate_line_item_path(zero_tax_estimate, line_item)
      wait_for_js

      input = open_material_slot(:exterior)
      type_into_tom_select(input, "Maple")

      # Wait for the filter to be applied — the dropdown initially shows all
      # options and Tom Select removes non-matches asynchronously after typing.
      expect(page).to have_css(".ts-dropdown-content .option", text: "Maple Plywood", wait: 3)
      expect(page).to have_no_css(".ts-dropdown-content .option", text: "Birch Plywood", wait: 3)
    end

    # Scenario C — full inline find-or-create flow ending in saved line item with the new material slot populated
    it "creates a new material inline, selects it, saves the line item, and shows non-zero material cost" do
      line_item = create(:line_item, estimate: zero_tax_estimate, description: "Inline Create Cabinet", quantity: 1)

      login
      visit edit_estimate_line_item_path(zero_tax_estimate, line_item)
      wait_for_js

      input = open_material_slot(:exterior)
      type_into_tom_select(input, "Acrylic Panel")

      # The custom no_results render shows the "Add 'Acrylic Panel'" option.
      # A plain Capybara .click works here because the "Add" element is a div
      # outside Tom Select's option list — it has its own mousedown listener
      # and is not subject to the framework's option-click handling that the
      # click_tom_select_option helper exists to work around.
      add_option = find(".ts-dropdown .add-new-option", text: /Add 'Acrylic Panel'/, wait: 3)
      add_option.click

      # Inline create panel appears inside the dropdown.
      panel = find(".ts-dropdown .inline-create-panel", wait: 3)
      within(panel) do
        # Name field is pre-filled with the typed text.  Using fill_in with the
        # label text verifies the label-for/input-id association works.
        expect(page).to have_field("Material name", with: "Acrylic Panel")
        fill_in "Cost ($)", with: "28.00"
        find(".inline-create-confirm").click
      end

      # Wait for fetch round-trip and Tom Select to add+select+close.
      expect(page).to have_no_css(".inline-create-panel", wait: 5)

      # The selected display item should now read "Acrylic Panel ($28.00)".
      expect(page).to have_css(".ts-wrapper .item", text: /Acrylic Panel \(\$28\.00\)/, wait: 3)

      fill_in "line_item[exterior_qty]", with: "2"

      find("input[type='submit']").click
      expect(page).to have_current_path(edit_estimate_path(zero_tax_estimate), wait: 5)

      material = Material.find_by(name: "Acrylic Panel")
      expect(material).to be_present
      em = zero_tax_estimate.estimate_materials.find_by(material_id: material.id)
      expect(em).to be_present
      expect(em.quote_price).to eq(BigDecimal("28.00"))

      line_item.reload
      expect(line_item.exterior_material_id).to eq(em.id)

      within("#line_item_#{line_item.id}") do
        expect(page).to have_text("$56.00", wait: 3)
      end
    end

    # Scenario D — inline create error surfaces in the panel without closing the dropdown
    it "shows errors inside the dropdown when cost is blank and does not create a Material" do
      line_item = create(:line_item, estimate: zero_tax_estimate, description: "Error Test", quantity: 1)

      login
      visit edit_estimate_line_item_path(zero_tax_estimate, line_item)
      wait_for_js

      input = open_material_slot(:exterior)
      type_into_tom_select(input, "Cedar Ply")

      find(".ts-dropdown .add-new-option", text: /Add 'Cedar Ply'/, wait: 3).click

      panel = find(".ts-dropdown .inline-create-panel", wait: 3)
      within(panel) do
        # Leave cost blank.
        find(".inline-create-confirm").click
        expect(page).to have_css(".inline-create-errors", visible: true, wait: 5)
      end

      # Dropdown stays open; panel stays visible.
      expect(page).to have_css(".ts-dropdown .inline-create-panel")

      # No Material was created.
      expect(Material.where(name: "Cedar Ply")).to be_empty
    end
  end
end
