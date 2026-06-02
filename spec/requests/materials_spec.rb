require "rails_helper"

RSpec.describe "Materials", type: :request do
  let(:user) { create(:user) }
  before { sign_in(user) }

  describe "GET /materials" do
    it "returns http ok" do
      get materials_path
      expect(response).to have_http_status(:ok)
    end

    it "shows active materials ordered by name" do
      create(:material, name: "Zebra Wood")
      create(:material, name: "Alder Sheet")
      get materials_path
      expect(response.body.index("Alder Sheet")).to be < response.body.index("Zebra Wood")
    end

    it "does not render pagination when material count is 20 or fewer" do
      create_list(:material, 5)
      get materials_path
      expect(response).to have_http_status(:ok)
      expect(response.body).not_to include('class="pagy nav"')
    end

    it "shows active materials" do
      material = create(:material, name: "Maple Plywood")
      get materials_path
      expect(response.body).to include("Maple Plywood")
    end

    it "does not show soft-deleted materials" do
      discarded = create(:material, name: "Old Sheet", discarded_at: 1.day.ago)
      get materials_path
      expect(response.body).not_to include("Old Sheet")
    end

    it "redirects to login when unauthenticated" do
      delete session_path
      get materials_path
      expect(response).to redirect_to(new_session_path)
    end
  end

  describe "GET /materials?q=maple" do
    before do
      create(:material, name: "Maple Plywood", description: "Top grade")
      create(:material, name: "Oak Veneer",    description: "Hardwood oak")
    end

    it "returns 200" do
      get materials_path, params: { q: "maple" }
      expect(response).to have_http_status(:ok)
    end

    it "shows matching materials" do
      get materials_path, params: { q: "maple" }
      expect(response.body).to include("Maple Plywood")
    end

    it "excludes non-matching materials" do
      get materials_path, params: { q: "maple" }
      expect(response.body).not_to include("Oak Veneer")
    end
  end

  describe "GET /materials?q=nomatch" do
    it "returns 200 and shows the empty search state message" do
      get materials_path, params: { q: "nomatch_zzzz" }
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("No materials matched your search.")
    end
  end

  describe "GET /materials?q=maple&page=2" do
    before do
      25.times { |i| create(:material, name: "Maple Board #{i.to_s.rjust(2, '0')}") }
    end

    it "returns 200 for page 2 of a filtered result set" do
      get materials_path, params: { q: "maple", page: 2 }
      expect(response).to have_http_status(:ok)
    end
  end

  describe "GET /materials?page=9999" do
    before { create(:material) }

    it "redirects to the last valid page" do
      get materials_path, params: { page: 9999 }
      expect(response).to redirect_to(materials_path(q: "", page: 1))
    end
  end

  describe "POST /materials" do
    let(:valid_params) do
      { material: { name: "Maple Plywood 3/4", category: "sheet_good", default_price: "68.00", unit: "sheet" } }
    end

    it "creates a material and redirects" do
      expect {
        post materials_path, params: valid_params
      }.to change(Material, :count).by(1)
      expect(response).to redirect_to(materials_path)
    end

    it "returns unprocessable entity with invalid params" do
      post materials_path, params: { material: { name: "", category: "sheet_good", default_price: "10" } }
      expect(response).to have_http_status(:unprocessable_content)
    end

    it "redirects to login when unauthenticated" do
      delete session_path
      post materials_path, params: valid_params
      expect(response).to redirect_to(new_session_path)
    end
  end

  describe "PATCH /materials/:id" do
    let!(:material) { create(:material, name: "Old Name") }

    it "updates the material and redirects" do
      patch material_path(material), params: { material: { name: "New Name", category: "hardware", default_price: "5.00" } }
      expect(response).to redirect_to(materials_path)
      expect(material.reload.name).to eq("New Name")
    end

    it "returns unprocessable entity with invalid params" do
      patch material_path(material), params: { material: { name: "", category: "sheet_good", default_price: "0" } }
      expect(response).to have_http_status(:unprocessable_content)
    end
  end

  describe "DELETE /materials/:id" do
    context "when material has no estimate_materials rows" do
      let!(:material) { create(:material) }

      it "soft-deletes the material and redirects" do
        delete material_path(material)
        expect(response).to redirect_to(materials_path)
        expect(material.reload.discarded_at).to be_present
      end
    end

    context "when material has active estimate_materials rows" do
      let!(:material) { create(:material) }
      let!(:estimate) { create(:estimate) }
      let!(:em)       { create(:estimate_material, estimate: estimate, material: material) }

      it "does not soft-delete the material" do
        delete material_path(material)
        expect(material.reload.discarded_at).to be_nil
      end

      it "redirects with an error alert" do
        delete material_path(material)
        expect(response).to redirect_to(materials_path)
        expect(flash[:alert]).to be_present
      end
    end

    it "redirects to login when unauthenticated" do
      delete session_path
      material = create(:material)
      delete material_path(material)
      expect(response).to redirect_to(new_session_path)
    end
  end
end
