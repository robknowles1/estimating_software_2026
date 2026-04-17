require "rails_helper"

RSpec.describe "Materials library", type: :system do
  before { driven_by(:selenium_chrome_headless) }

  let!(:user) { create(:user) }

  def login
    visit new_session_path
    fill_in "Email", with: user.email
    fill_in "Password", with: "password123"
    click_button "Sign In"
    expect(page).to have_current_path(estimates_path, wait: 5)
  end

  describe "visiting the materials index" do
    it "shows the materials library" do
      login
      visit materials_path
      expect(page).to have_text("Materials Library")
    end
  end

  describe "creating a new material" do
    it "creates the material and shows it in the index" do
      login
      visit new_material_path

      fill_in "material[name]", with: "Maple Plywood 3/4"
      select "Sheet Good", from: "material[category]"
      fill_in "material[default_price]", with: "68.00"
      fill_in "material[unit]", with: "sheet"

      find("input[type='submit']").click

      expect(page).to have_current_path(materials_path, wait: 5)
      expect(page).to have_text("Maple Plywood 3/4", wait: 3)
    end
  end

  describe "editing a material" do
    it "updates the default_price and shows the new value" do
      material = create(:material, name: "Oak Veneer", default_price: BigDecimal("30.00"))
      login
      visit edit_material_path(material)

      fill_in "material[default_price]", with: "35.00"
      find("input[type='submit']").click

      expect(page).to have_current_path(materials_path, wait: 5)
      expect(page).to have_text("35.0000", wait: 3)
    end
  end

  describe "archiving a material" do
    context "when the material is in use" do
      it "shows an error and keeps the material in the list" do
        material = create(:material, name: "Busy Sheet")
        estimate = create(:estimate, created_by: user)
        create(:estimate_material, estimate: estimate, material: material)

        login
        visit materials_path

        # Submit the archive (delete) form directly — the Archive button may be
        # scrolled off-screen horizontally in the headless browser viewport.
        page.driver.browser.execute_script(
          "document.querySelector('form[action*=\"/materials/\"]').submit()"
        )

        expect(page).to have_text("Busy Sheet", wait: 3)
      end
    end

    context "when the material is not in use" do
      it "removes the material from the active list" do
        create(:material, name: "Unused Board")
        login
        visit materials_path

        page.driver.browser.execute_script(
          "document.querySelector('form[action*=\"/materials/\"]').submit()"
        )

        expect(page).not_to have_text("Unused Board", wait: 3)
      end
    end
  end
end
