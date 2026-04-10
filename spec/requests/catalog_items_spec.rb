require "rails_helper"

RSpec.describe "CatalogItems", type: :request do
  let(:user) { create(:user) }

  before { sign_in(user) }

  describe "GET /catalog_items" do
    it "returns ok and lists catalog items" do
      create(:catalog_item, description: "Crown Moulding")
      get catalog_items_path
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Crown Moulding")
    end

    it "redirects to login when not authenticated" do
      delete session_path
      get catalog_items_path
      expect(response).to redirect_to(new_session_path)
    end

    it "filters by category when category param is present" do
      create(:catalog_item, description: "Crown Moulding", category: "millwork")
      create(:catalog_item, description: "Delivery",       category: "general_conditions")
      get catalog_items_path(category: "millwork")
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Crown Moulding")
      expect(response.body).not_to include("Delivery")
    end
  end

  describe "GET /catalog_items/search" do
    it "redirects to login when not authenticated" do
      delete session_path
      get search_catalog_items_path, params: { q: "door" }
      expect(response).to redirect_to(new_session_path)
    end

    context "when authenticated" do
      let!(:door_item)  { create(:catalog_item, description: "Door Casing", default_unit: "LF", default_unit_cost: 12.50) }
      let!(:hinge_item) { create(:catalog_item, description: "Concealed Hinge") }

      it "returns JSON array with matching items" do
        get search_catalog_items_path, params: { q: "door" }, headers: { "Accept" => "application/json" }
        expect(response).to have_http_status(:ok)
        expect(response.content_type).to include("application/json")
        json = JSON.parse(response.body)
        expect(json.length).to eq(1)
        expect(json.first["description"]).to eq("Door Casing")
        expect(json.first["default_unit"]).to eq("LF")
        expect(json.first["default_unit_cost"]).to eq("12.5")
      end

      it "returns empty array when no matches" do
        get search_catalog_items_path, params: { q: "zzz_no_match" }, headers: { "Accept" => "application/json" }
        expect(response).to have_http_status(:ok)
        json = JSON.parse(response.body)
        expect(json).to be_empty
      end

      it "returns empty array when query is shorter than 2 characters" do
        get search_catalog_items_path, params: { q: "d" }, headers: { "Accept" => "application/json" }
        expect(response).to have_http_status(:ok)
        json = JSON.parse(response.body)
        expect(json).to be_empty
      end

      it "returns empty array when query param is absent" do
        get search_catalog_items_path, headers: { "Accept" => "application/json" }
        expect(response).to have_http_status(:ok)
        json = JSON.parse(response.body)
        expect(json).to be_empty
      end

      it "returns id, description, default_unit, default_unit_cost in each result" do
        get search_catalog_items_path, params: { q: "door" }, headers: { "Accept" => "application/json" }
        json = JSON.parse(response.body)
        expect(json.first.keys).to match_array(%w[id description default_unit default_unit_cost])
      end
    end
  end

  describe "POST /catalog_items" do
    it "creates a catalog item with valid params and redirects" do
      expect {
        post catalog_items_path, params: {
          catalog_item: {
            description: "New Item",
            default_unit: "EA",
            default_unit_cost: "15.00",
            category: "millwork"
          }
        }
      }.to change(CatalogItem, :count).by(1)
      expect(response).to redirect_to(catalog_items_path)
    end

    it "does not create with blank description" do
      expect {
        post catalog_items_path, params: {
          catalog_item: { description: "", default_unit: "EA" }
        }
      }.not_to change(CatalogItem, :count)
      expect(response).to have_http_status(:unprocessable_content)
    end
  end

  describe "PATCH /catalog_items/:id" do
    let(:catalog_item) { create(:catalog_item, description: "Original") }

    it "updates the catalog item and redirects" do
      patch catalog_item_path(catalog_item), params: {
        catalog_item: { description: "Updated Description" }
      }
      expect(response).to redirect_to(catalog_items_path)
      expect(catalog_item.reload.description).to eq("Updated Description")
    end

    it "returns unprocessable_content with blank description" do
      patch catalog_item_path(catalog_item), params: {
        catalog_item: { description: "" }
      }
      expect(response).to have_http_status(:unprocessable_content)
    end
  end

  describe "DELETE /catalog_items/:id" do
    let(:catalog_item) { create(:catalog_item) }
    let(:estimate_section) { create(:estimate_section) }
    let!(:line_item) do
      create(:line_item, estimate_section: estimate_section, catalog_item: catalog_item)
    end

    it "destroys the catalog item and redirects" do
      expect { delete catalog_item_path(catalog_item) }.to change(CatalogItem, :count).by(-1)
      expect(response).to redirect_to(catalog_items_path)
    end

    it "nullifies catalog_item_id on associated line items" do
      delete catalog_item_path(catalog_item)
      expect(line_item.reload.catalog_item_id).to be_nil
    end

    it "does not delete associated line items" do
      expect { delete catalog_item_path(catalog_item) }.not_to change(LineItem, :count)
    end
  end
end
