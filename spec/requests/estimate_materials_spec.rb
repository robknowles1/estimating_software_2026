require "rails_helper"

RSpec.describe "EstimateMaterials", type: :request do
  let(:user) { create(:user) }
  let(:estimate) { create(:estimate, :skip_material_seeding, created_by: user) }
  let!(:pl1) { create(:estimate_material, estimate: estimate, category: "pl", slot_number: 1, price_per_unit: BigDecimal("0.00")) }

  before { sign_in(user) }

  describe "PATCH /estimates/:id/materials" do
    it "updates EstimateMaterial prices and redirects" do
      patch estimate_materials_path(estimate),
        params: { estimate_materials: { pl1.id => { description: "WD2", price_per_unit: "75.50", unit: "sheet" } } }

      pl1.reload
      expect(pl1.description).to eq("WD2")
      expect(pl1.price_per_unit).to eq(BigDecimal("75.50"))
      expect(response).to redirect_to(edit_estimate_materials_path(estimate))
    end
  end

  describe "PATCH /estimates/:id with job-level settings" do
    it "persists job-level settings on the estimate" do
      patch estimate_path(estimate),
        params: {
          estimate: {
            title: estimate.title,
            client_id: estimate.client_id,
            miles_to_jobsite: "42.5",
            installer_crew_size: "3",
            profit_overhead_percent: "20.0"
          }
        }

      estimate.reload
      expect(estimate.miles_to_jobsite).to eq(BigDecimal("42.5"))
      expect(estimate.installer_crew_size).to eq(3)
      expect(estimate.profit_overhead_percent).to eq(BigDecimal("20.0"))
    end
  end
end
