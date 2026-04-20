require "rails_helper"

RSpec.describe "MaterialSets", type: :request do
  let(:user) { create(:user) }
  before { sign_in(user) }

  describe "POST /material_sets/:id/apply_to_estimate" do
    let(:estimate)      { create(:estimate, created_by: user) }
    let(:material_set)  { create(:material_set) }
    let!(:mat1)         { create(:material, default_price: BigDecimal("30.00")) }
    let!(:mat2)         { create(:material, default_price: BigDecimal("20.00")) }

    before do
      material_set.material_set_items.create!(material: mat1)
      material_set.material_set_items.create!(material: mat2)
    end

    it "creates estimate_materials rows for each item" do
      expect {
        post apply_to_estimate_material_set_path(material_set), params: { estimate_id: estimate.id }
      }.to change(EstimateMaterial, :count).by(2)
    end

    it "sets quote_price from material.default_price" do
      post apply_to_estimate_material_set_path(material_set), params: { estimate_id: estimate.id }
      em1 = estimate.estimate_materials.find_by(material: mat1)
      expect(em1.quote_price).to eq(BigDecimal("30.00"))
    end

    it "redirects to the estimate's estimate_materials index" do
      post apply_to_estimate_material_set_path(material_set), params: { estimate_id: estimate.id }
      expect(response).to redirect_to(estimate_estimate_materials_path(estimate))
    end

    it "skips materials already present on the estimate" do
      create(:estimate_material, estimate: estimate, material: mat1)
      expect {
        post apply_to_estimate_material_set_path(material_set), params: { estimate_id: estimate.id }
      }.to change(EstimateMaterial, :count).by(1)
    end

    it "includes added and skipped counts in the notice" do
      create(:estimate_material, estimate: estimate, material: mat1)
      post apply_to_estimate_material_set_path(material_set), params: { estimate_id: estimate.id }
      expect(flash[:notice]).to include("1")
    end

    it "returns 404 with an invalid estimate_id" do
      post apply_to_estimate_material_set_path(material_set), params: { estimate_id: 0 }
      expect(response).to have_http_status(:not_found)
    end
  end

  it "redirects to login when unauthenticated" do
    delete session_path
    ms = create(:material_set)
    estimate = create(:estimate)
    post apply_to_estimate_material_set_path(ms), params: { estimate_id: estimate.id }
    expect(response).to redirect_to(new_session_path)
  end

  describe "POST /material_sets (create) — discarded material in submission" do
    it "does not link a discarded material when its ID is submitted" do
      discarded = create(:material, discarded_at: Time.current)
      active    = create(:material)

      post material_sets_path, params: {
        material_set: {
          name:         "Mixed Set",
          material_ids: [ discarded.id.to_s, active.id.to_s ]
        }
      }

      ms = MaterialSet.find_by!(name: "Mixed Set")
      linked_ids = ms.material_set_items.pluck(:material_id)
      expect(linked_ids).to include(active.id)
      expect(linked_ids).not_to include(discarded.id)
    end
  end
end
