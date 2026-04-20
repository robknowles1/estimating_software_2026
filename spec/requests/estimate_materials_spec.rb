require "rails_helper"

RSpec.describe "EstimateMaterials", type: :request do
  let(:user)     { create(:user) }
  let(:estimate) { create(:estimate, created_by: user, tax_rate: BigDecimal("0.10"), tax_exempt: false) }

  before { sign_in(user) }

  describe "GET /estimates/:estimate_id/estimate_materials/new" do
    it "includes active material names in the combobox data attribute" do
      material = create(:material, name: "Cherry Plywood", category: "sheet_good")
      get new_estimate_estimate_material_path(estimate)
      expect(response.body).to include("Cherry Plywood")
    end

    it "sets the combobox materials value to an empty JSON array when no active materials exist" do
      get new_estimate_estimate_material_path(estimate)
      expect(response.body).to include("data-material-combobox-materials-value=\"[]\"")
    end
  end

  describe "GET /estimates/:estimate_id/estimate_materials" do
    it "returns http ok" do
      get estimate_estimate_materials_path(estimate)
      expect(response).to have_http_status(:ok)
    end

    it "lists the estimate's materials" do
      material = create(:material, name: "Birch Ply")
      create(:estimate_material, estimate: estimate, material: material)
      get estimate_estimate_materials_path(estimate)
      expect(response.body).to include("Birch Ply")
    end

    it "redirects to login when unauthenticated" do
      delete session_path
      get estimate_estimate_materials_path(estimate)
      expect(response).to redirect_to(new_session_path)
    end
  end

  describe "POST /estimates/:estimate_id/estimate_materials with material_id" do
    let!(:material) { create(:material, name: "Oak Sheet", default_price: BigDecimal("55.00")) }

    it "creates an estimate_materials row with quote_price from default_price" do
      expect {
        post estimate_estimate_materials_path(estimate), params: { material_id: material.id }
      }.to change(EstimateMaterial, :count).by(1)

      em = estimate.estimate_materials.last
      expect(em.quote_price).to eq(BigDecimal("55.00"))
      expect(em.material).to eq(material)
    end

    it "redirects to the price book index" do
      post estimate_estimate_materials_path(estimate), params: { material_id: material.id }
      expect(response).to redirect_to(estimate_estimate_materials_path(estimate))
    end

    it "does not create a duplicate when material is already present" do
      create(:estimate_material, estimate: estimate, material: material)
      expect {
        post estimate_estimate_materials_path(estimate), params: { material_id: material.id }
      }.not_to change(EstimateMaterial, :count)
    end

    it "redirects with an informational notice when material already present" do
      create(:estimate_material, estimate: estimate, material: material)
      post estimate_estimate_materials_path(estimate), params: { material_id: material.id }
      expect(response).to redirect_to(estimate_estimate_materials_path(estimate))
      expect(flash[:notice]).to include("already")
    end
  end

  describe "POST /estimates/:estimate_id/estimate_materials with new material params" do
    let(:new_material_params) do
      {
        material: {
          name:          "Custom Hardwood",
          category:      "sheet_good",
          default_price: "75.00",
          unit:          "sheet"
        }
      }
    end

    it "creates a Material and an EstimateMaterial in one request" do
      expect {
        post estimate_estimate_materials_path(estimate), params: new_material_params
      }.to change(Material, :count).by(1)
        .and change(EstimateMaterial, :count).by(1)
    end

    it "redirects to the price book index" do
      post estimate_estimate_materials_path(estimate), params: new_material_params
      expect(response).to redirect_to(estimate_estimate_materials_path(estimate))
    end
  end

  describe "PATCH /estimates/:estimate_id/estimate_materials/:id" do
    let!(:material) { create(:material, default_price: BigDecimal("50.00")) }
    let!(:em)       { create(:estimate_material, estimate: estimate, material: material, quote_price: BigDecimal("50.00")) }

    it "updates quote_price and recomputes cost_with_tax" do
      patch estimate_estimate_material_path(estimate, em), params: {
        estimate_material: { quote_price: "60.00" }
      }
      em.reload
      expect(em.quote_price).to eq(BigDecimal("60.00"))
      expect(em.cost_with_tax).to eq(BigDecimal("60.00") * BigDecimal("1.10"))
    end

    it "redirects to the price book index" do
      patch estimate_estimate_material_path(estimate, em), params: {
        estimate_material: { quote_price: "60.00" }
      }
      expect(response).to redirect_to(estimate_estimate_materials_path(estimate))
    end
  end

  describe "strong params — removed flat columns" do
    it "does not permit exterior_unit_price on line item create" do
      post estimate_line_items_path(estimate), params: {
        line_item: {
          description: "Test",
          quantity: "1",
          unit: "EA",
          exterior_unit_price: "999"
        }
      }
      li = LineItem.last
      expect(li).not_to respond_to(:exterior_unit_price)
    end

    it "does not permit exterior_description on line item create" do
      post estimate_line_items_path(estimate), params: {
        line_item: {
          description: "Test2",
          quantity: "1",
          unit: "EA",
          exterior_description: "ignored"
        }
      }
      li = LineItem.last
      expect(li).not_to respond_to(:exterior_description)
    end
  end

  describe "POST /estimates/:estimate_id/estimate_materials — soft-deleted material" do
    it "returns 404 when the material is soft-deleted" do
      material = create(:material, discarded_at: Time.current)
      post estimate_estimate_materials_path(estimate), params: { material_id: material.id }
      expect(response).to have_http_status(:not_found)
    end
  end

  describe "POST /estimates/:estimate_id/estimate_materials — race condition on duplicate" do
    it "redirects with already_present notice instead of raising on RecordNotUnique" do
      material = create(:material)
      # Pre-create the record so the unique index is violated
      create(:estimate_material, estimate: estimate, material: material)
      # Force the race: em.save will hit the DB unique constraint because find_or_initialize
      # is not used anymore — the duplicate check is now handled by rescuing RecordNotUnique
      post estimate_estimate_materials_path(estimate), params: { material_id: material.id }
      expect(response).to redirect_to(estimate_estimate_materials_path(estimate))
      expect(flash[:notice]).to include("already")
    end
  end

  describe "POST /estimates/:estimate_id/estimate_materials — new material transaction atomicity" do
    it "creates both Material and EstimateMaterial together" do
      params = {
        material: {
          name:          "Brand New Material",
          category:      "sheet_good",
          default_price: "10.00",
          unit:          "sheet"
        }
      }
      expect {
        post estimate_estimate_materials_path(estimate), params: params
      }.to change(Material, :count).by(1).and change(EstimateMaterial, :count).by(1)
    end

    it "does not leave an orphaned Material when only material params are invalid" do
      # category missing — material fails validation, nothing is created
      params = { material: { name: "", category: "", default_price: "10.00", unit: "sheet" } }
      expect {
        post estimate_estimate_materials_path(estimate), params: params
      }.not_to change(Material, :count)
      expect(response).to have_http_status(:unprocessable_content)
    end

    it "rolls back the Material when EstimateMaterial save fails" do
      # Force the EstimateMaterial save to fail (simulates e.g. a uniqueness violation on the EM
      # side after the material has already been persisted within the same transaction).
      allow_any_instance_of(EstimateMaterial).to receive(:save).and_return(false)

      params = {
        material: {
          name:          "Orphan Risk Material",
          category:      "sheet_good",
          default_price: "20.00",
          unit:          "sheet"
        }
      }
      expect {
        post estimate_estimate_materials_path(estimate), params: params
      }.not_to change(Material, :count)
    end
  end

  describe "unauthenticated access" do
    before { delete session_path }

    it "redirects GET index to login" do
      get estimate_estimate_materials_path(estimate)
      expect(response).to redirect_to(new_session_path)
    end

    it "redirects POST create to login" do
      post estimate_estimate_materials_path(estimate), params: { material_id: "1" }
      expect(response).to redirect_to(new_session_path)
    end
  end
end
