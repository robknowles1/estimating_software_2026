require "rails_helper"

RSpec.describe "Products", type: :system do
  before { driven_by(:selenium_chrome_headless) }

  let!(:user) { create(:user) }

  def login(as: user, password: "password123")
    visit new_session_path
    fill_in "Email", with: as.email
    fill_in "Password", with: password
    click_button "Sign In"
    expect(page).to have_current_path(estimates_path, wait: 5)
  end

  describe "creating a product" do
    it "creates a product and shows it in the index" do
      login
      visit new_product_path

      fill_in "product[name]", with: "MDF Base 2-door"
      fill_in "product[unit]", with: "EA"
      fill_in "product[category]", with: "Base Cabinets"
      find("input[type='submit']").click

      expect(page).to have_current_path(products_path, wait: 5)
      expect(page).to have_text("MDF Base 2-door")
    end
  end

  describe "editing a product" do
    it "updates the product name and shows the new name in the index" do
      product = create(:product, name: "Old Cabinet Name")

      login
      visit edit_product_path(product)

      fill_in "product[name]", with: "Updated Cabinet Name"
      find("input[type='submit']").click

      expect(page).to have_current_path(products_path, wait: 5)
      expect(page).to have_text("Updated Cabinet Name")
      expect(page).not_to have_text("Old Cabinet Name")
    end
  end

  describe "deleting a product" do
    it "removes the product from the index and nullifies associated line item product_id" do
      product   = create(:product, name: "Deletable Cabinet")
      estimate  = create(:estimate)
      line_item = create(:line_item, estimate: estimate, description: "My Item", product: product)

      login
      visit products_path

      delete_button = find("tr", text: "Deletable Cabinet").find("button", text: "Delete", visible: false)
      page.execute_script("arguments[0].scrollIntoView(true)", delete_button)

      accept_confirm do
        delete_button.click
      end

      expect(page).to have_current_path(products_path, wait: 5)
      expect(page).not_to have_text("Deletable Cabinet")

      line_item.reload
      expect(line_item.description).to eq("My Item")
      expect(line_item.product_id).to be_nil
    end
  end
end
