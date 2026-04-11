require "rails_helper"

RSpec.describe "Estimates::Materials", type: :request do
  let(:user)     { create(:user) }
  let(:estimate) { create(:estimate, :skip_material_seeding, created_by: user) }
  let!(:pl1) do
    create(:material, estimate: estimate, slot_key: "PL1", category: "sheet_good",
                       quote_price: BigDecimal("0.00"))
  end
  let!(:hinge1) do
    create(:material, estimate: estimate, slot_key: "HINGE1", category: "hardware",
                       quote_price: BigDecimal("0.00"))
  end

  before { sign_in(user) }

  describe "GET /estimates/:id/materials/edit" do
    it "returns http ok" do
      get edit_estimate_materials_path(estimate)
      expect(response).to have_http_status(:ok)
    end

    it "renders all material slots" do
      get edit_estimate_materials_path(estimate)
      expect(response.body).to include("PL1")
      expect(response.body).to include("HINGE1")
    end

    it "renders slots grouped by category — Sheet Goods and Hardware sections visible" do
      get edit_estimate_materials_path(estimate)
      expect(response.body).to include("Sheet Goods")
      expect(response.body).to include("Hardware")
    end
  end

  describe "PATCH /estimates/:id/materials" do
    it "updates quote_price and recalculates cost_with_tax, then redirects" do
      patch estimate_materials_path(estimate),
        params: { materials: { pl1.id.to_s => { description: "Maple Ply", quote_price: "75.50" } } }

      pl1.reload
      expect(pl1.description).to eq("Maple Ply")
      expect(pl1.quote_price).to eq(BigDecimal("75.50"))
      # cost_with_tax = 75.50 * (1 + estimate.tax_rate)
      expected_cost = BigDecimal("75.50") * (BigDecimal("1") + estimate.tax_rate)
      expect(pl1.cost_with_tax).to eq(expected_cost)
      expect(response).to redirect_to(edit_estimate_materials_path(estimate))
    end

    it "shows a success flash notice after update" do
      patch estimate_materials_path(estimate),
        params: { materials: { pl1.id.to_s => { quote_price: "50.00" } } }
      follow_redirect!
      expect(response.body).to include("Material costs updated successfully")
    end
  end
end
