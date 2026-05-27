require "rails_helper"

RSpec.describe "Material alias auto-population", type: :system do
  before { driven_by(:selenium_chrome_headless) }

  def login(user)
    visit new_session_path
    fill_in "Email", with: user.email
    fill_in "Password", with: "password123"
    click_button "Sign In"
    expect(page).to have_current_path(estimates_path, wait: 5)
  end

  def import_csv_via_details
    # The estimate edit page has two <details> elements; the import one contains
    # the CSV file input. Use JS to set the open attribute reliably in headless Chrome.
    import_details = all("details").find { |det| det.text.include?("Import CSV") }
    page.execute_script("arguments[0].setAttribute('open', '')", import_details.native)
    # Wait for the file input to become visible before attaching
    within(import_details) do
      find("input[type='file']", visible: :visible, wait: 5)
      attach_file "csv_file", Rails.root.join("spec/fixtures/files/sample_import.csv")
      # Use JS-driven click to submit the form reliably in headless Chrome
      submit_btn = find("input[type='submit']")
      page.execute_script("arguments[0].click()", submit_btn.native)
    end
  end

  # scenario 1: assign short code and see it on the index page
  describe "assigning a short code to a price book entry" do
    it "shows the Short Code field on the edit form and displays the badge on the index" do
      # Arrange
      user     = create(:user)
      client   = create(:client, company_name: "Prestige Millwork")
      estimate = create(:estimate, client: client, title: "Kitchen Job", created_by: user,
                        tax_rate: BigDecimal("0.10"), tax_exempt: false)
      material = create(:material, name: "Maple Plywood 3/4", default_price: BigDecimal("68.00"))
      create(:estimate_material, estimate: estimate, material: material,
             quote_price: BigDecimal("68.00"))
      login(user)

      # Act
      visit estimate_estimate_materials_path(estimate)
      click_link "Edit", match: :first

      expect(page).to have_field("estimate_material[short_code]")
      fill_in "estimate_material[quote_price]", with: "68.00"
      fill_in "estimate_material[short_code]", with: "PL1"
      # Use JS-driven click to avoid headless Chrome swallowing the submit click
      page.execute_script("document.querySelector('input[type=\"submit\"]').click()")

      # Assert
      expect(page).to have_current_path(estimate_estimate_materials_path(estimate), wait: 5)
      expect(page).to have_text("PL1", wait: 3)
    end
  end

  # scenario 2: line item whose description matches a short code shows no "Needs review" badge
  describe "line item with matching short code shows no Needs review badge" do
    it "does not show a Needs review badge on the matched line item" do
      # Arrange
      user     = create(:user)
      client   = create(:client, company_name: "Prestige Millwork")
      estimate = create(:estimate, client: client, title: "Kitchen Job", created_by: user,
                        tax_rate: BigDecimal("0.10"), tax_exempt: false)
      material = create(:material, name: "Maple Plywood 3/4", default_price: BigDecimal("68.00"))
      em       = create(:estimate_material, estimate: estimate, material: material,
                        quote_price: BigDecimal("68.00"))
      em.update!(short_code: "PL1")
      matched_li = create(:line_item, estimate: estimate, description: "PL1 Base Cabinet")
      login(user)

      # Act
      visit edit_estimate_path(estimate)

      # Assert
      expect(page).to have_text("PL1 Base Cabinet", wait: 5)
      matched_card = find("[id='#{ActionView::RecordIdentifier.dom_id(matched_li)}']")
      within(matched_card) do
        expect(page).not_to have_text("Needs review")
      end
    end
  end

  # scenario 3: CSV import with a short code that does not appear in imported product names
  # The badge logic requires: at least one short code configured AND no short code matches the
  # description. If no short codes are configured at all, no badge is shown (correct behavior).
  describe "CSV import with no matching short code" do
    it "shows Needs review badge on unmatched line items when a short code is configured but does not match" do
      # Arrange — em has short_code "XYZZY" which won't appear in "Base 2-Door" or "Wall Cabinet"
      user     = create(:user)
      client   = create(:client, company_name: "Prestige Millwork")
      estimate = create(:estimate, client: client, title: "Kitchen Job", created_by: user,
                        tax_rate: BigDecimal("0.10"), tax_exempt: false)
      material = create(:material, name: "Maple Plywood 3/4", default_price: BigDecimal("68.00"))
      em       = create(:estimate_material, estimate: estimate, material: material,
                        quote_price: BigDecimal("68.00"), short_code: "XYZZY")
      login(user)

      # Act
      visit edit_estimate_path(estimate)
      import_csv_via_details

      # Assert
      expect(page).to have_current_path(edit_estimate_path(estimate), wait: 5)
      expect(page).to have_text("Needs review", wait: 5)
    end

    it "still shows the Needs review badge after manual material assignment" do
      # Arrange — short code "XYZZY" won't match any imported product name
      user     = create(:user)
      client   = create(:client, company_name: "Prestige Millwork")
      estimate = create(:estimate, client: client, title: "Kitchen Job", created_by: user,
                        tax_rate: BigDecimal("0.10"), tax_exempt: false)
      material = create(:material, name: "Maple Plywood 3/4", default_price: BigDecimal("68.00"))
      em       = create(:estimate_material, estimate: estimate, material: material,
                        quote_price: BigDecimal("68.00"), short_code: "XYZZY")
      login(user)

      # Act
      visit edit_estimate_path(estimate)
      import_csv_via_details
      expect(page).to have_current_path(edit_estimate_path(estimate), wait: 5)
      expect(page).to have_text("Needs review", wait: 5)

      # Manually assign a material via direct record update (simulating UI assignment)
      li = estimate.line_items.reload.last
      li.update!(exterior_material_id: em.id)

      visit edit_estimate_path(estimate)

      # Assert — badge still present because no short_code matched the description
      expect(page).to have_text("Needs review", wait: 3)
    end
  end

  # scenario 4: Apply short codes button re-runs matching
  describe "'Apply short codes to all line items' button" do
    it "clears Needs review badge for the line item after assigning its matching short code and clicking Apply" do
      # Arrange
      user     = create(:user)
      client   = create(:client, company_name: "Prestige Millwork")
      estimate = create(:estimate, client: client, title: "Kitchen Job", created_by: user,
                        tax_rate: BigDecimal("0.10"), tax_exempt: false)
      material  = create(:material, name: "Maple Plywood 3/4", default_price: BigDecimal("68.00"))
      material2 = create(:material, name: "MDF Sheet", default_price: BigDecimal("30.00"))
      em  = create(:estimate_material, estimate: estimate, material: material,
                   quote_price: BigDecimal("68.00"))
      em2 = create(:estimate_material, estimate: estimate, material: material2,
                   quote_price: BigDecimal("30.00"))
      em.update!(short_code: "PL1")
      create(:line_item, estimate: estimate, description: "SS5 Upper Cabinet")
      login(user)

      # Act — before: only PL1 short code on estimate; "SS5 Upper Cabinet" doesn't match
      visit edit_estimate_path(estimate)
      expect(page).to have_text("Needs review", wait: 3)

      # Assign SS5 to em2 and click Apply short codes
      em2.update!(short_code: "SS5")
      visit estimate_estimate_materials_path(estimate)
      expect(page).to have_button("Apply short codes to all line items")
      click_button "Apply short codes to all line items"

      # Assert
      expect(page).to have_current_path(edit_estimate_path(estimate), wait: 5)
      expect(page).to have_css("[role='status']", wait: 3)
      expect(page).not_to have_text("Needs review", wait: 3)
    end
  end

  # scenario 5: validation error on duplicate short code
  describe "duplicate short code validation" do
    it "shows a validation error when trying to save a duplicate short code" do
      # Arrange
      user     = create(:user)
      client   = create(:client, company_name: "Prestige Millwork")
      estimate = create(:estimate, client: client, title: "Kitchen Job", created_by: user,
                        tax_rate: BigDecimal("0.10"), tax_exempt: false)
      material  = create(:material, name: "Maple Plywood 3/4", default_price: BigDecimal("68.00"))
      material2 = create(:material, name: "MDF Sheet", default_price: BigDecimal("30.00"))
      create(:estimate_material, estimate: estimate, material: material,
             quote_price: BigDecimal("68.00"))
      create(:estimate_material, estimate: estimate, material: material2,
             quote_price: BigDecimal("30.00"), short_code: "PL1")
      login(user)

      # Act
      visit estimate_estimate_materials_path(estimate)
      click_link "Edit", match: :first

      fill_in "estimate_material[quote_price]", with: "68.00"
      fill_in "estimate_material[short_code]", with: "PL1"
      find("input[type='submit']").click

      # Assert — should stay on edit page with validation error
      expect(page).to have_text("Short code", wait: 3)
    end
  end
end
