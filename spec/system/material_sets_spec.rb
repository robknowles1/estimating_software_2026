require "rails_helper"

RSpec.describe "Material sets", type: :system do
  before { driven_by(:selenium_chrome_headless) }

  let!(:user)     { create(:user) }
  let!(:client)   { create(:client, company_name: "Prestige Millwork") }
  let!(:estimate) { create(:estimate, client: client, title: "Kitchen Job", created_by: user) }

  def login
    visit new_session_path
    fill_in "Email", with: user.email
    fill_in "Password", with: "password123"
    click_button "Sign In"
    expect(page).to have_current_path(estimates_path, wait: 5)
  end

  describe "creating a material set and adding library materials to it" do
    let!(:mat1) { create(:material, name: "Standard Maple Sheet", default_price: BigDecimal("55.00")) }
    let!(:mat2) { create(:material, name: "Maple Edge Banding",   default_price: BigDecimal("12.00")) }

    it "creates a set named 'Standard Maple' with two materials" do
      login
      visit new_material_set_path

      fill_in "material_set[name]", with: "Standard Maple"
      check mat1.name
      check mat2.name
      find("input[type='submit']").click

      expect(page).to have_current_path(material_sets_path, wait: 5)
      expect(page).to have_text("Standard Maple", wait: 3)

      ms = MaterialSet.find_by!(name: "Standard Maple")
      expect(ms.material_set_items.count).to eq(2)
    end
  end

  describe "applying a material set to an estimate" do
    let!(:mat1) { create(:material, name: "Standard Maple Sheet", default_price: BigDecimal("55.00")) }
    let!(:mat2) { create(:material, name: "Maple Edge Banding",   default_price: BigDecimal("12.00")) }
    let!(:material_set) do
      ms = create(:material_set, name: "Standard Maple")
      ms.material_set_items.create!(material: mat1)
      ms.material_set_items.create!(material: mat2)
      ms
    end

    it "applies the set and both materials appear in the price book" do
      login
      visit estimate_estimate_materials_path(estimate)

      # The apply-set UI uses a JS change handler on the select that builds and
      # submits a hidden POST form. CSRF protection is disabled in test, so we
      # build the form directly via execute_script without a CSRF token.
      select_url = apply_to_estimate_material_set_path(material_set)
      page.execute_script(<<~JS)
        const form = document.createElement("form");
        form.method = "post";
        form.action = "#{select_url}";
        const estInput = document.createElement("input");
        estInput.type = "hidden";
        estInput.name = "estimate_id";
        estInput.value = "#{estimate.id}";
        form.appendChild(estInput);
        document.body.appendChild(form);
        form.submit();
      JS

      expect(page).to have_current_path(estimate_estimate_materials_path(estimate), wait: 10)
      expect(page).to have_text("Standard Maple Sheet", wait: 5)
      expect(page).to have_text("Maple Edge Banding", wait: 5)
    end

    it "shows a confirmation notice when re-applying a set that is already present" do
      # Pre-add both materials so everything will be skipped
      create(:estimate_material, estimate: estimate, material: mat1, quote_price: mat1.default_price)
      create(:estimate_material, estimate: estimate, material: mat2, quote_price: mat2.default_price)

      login
      visit estimate_estimate_materials_path(estimate)

      select_url = apply_to_estimate_material_set_path(material_set)
      page.execute_script(<<~JS)
        const form = document.createElement("form");
        form.method = "post";
        form.action = "#{select_url}";
        const estInput = document.createElement("input");
        estInput.type = "hidden";
        estInput.name = "estimate_id";
        estInput.value = "#{estimate.id}";
        form.appendChild(estInput);
        document.body.appendChild(form);
        form.submit();
      JS

      expect(page).to have_current_path(estimate_estimate_materials_path(estimate), wait: 10)
      expect(page).to have_text("already present", wait: 5)
    end
  end
end
