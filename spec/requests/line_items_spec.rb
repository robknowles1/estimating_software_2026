require "rails_helper"

RSpec.describe "LineItems", type: :request do
  let(:user)     { create(:user) }
  let(:estimate) { create(:estimate, created_by: user) }

  before { sign_in(user) }

  describe "GET /estimates/:estimate_id/line_items/new" do
    it "returns http ok" do
      get new_estimate_line_item_path(estimate)
      expect(response).to have_http_status(:ok)
    end
  end

  describe "POST /estimates/:estimate_id/line_items" do
    context "without product_id (freeform)" do
      let(:freeform_params) do
        {
          line_item: {
            description: "Custom shelf unit",
            quantity: "2",
            unit: "EA"
          }
        }
      end

      it "creates a freeform line item with product_id nil" do
        expect {
          post estimate_line_items_path(estimate), params: freeform_params
        }.to change(LineItem, :count).by(1)

        expect(LineItem.last.product_id).to be_nil
      end

      it "saves the provided description" do
        post estimate_line_items_path(estimate), params: freeform_params
        expect(LineItem.last.description).to eq("Custom shelf unit")
      end

      it "ignores removed _material_id columns (schema no longer has them)" do
        post estimate_line_items_path(estimate), params: {
          line_item: {
            description: "Test",
            quantity: "1",
            unit: "EA",
            exterior_material_id: "999"  # filtered by strong params; column does not exist
          }
        }
        expect(response).to redirect_to(edit_estimate_path(estimate))
        expect(LineItem.last.description).to eq("Test")
        expect(LineItem.last.product_id).to be_nil
      end
    end

    context "with product_id" do
      let(:product) do
        create(:product,
               name: "MDF Base 2-door",
               unit: "EA",
               exterior_description: "MDF",
               exterior_unit_price: BigDecimal("45.00"),
               exterior_qty: BigDecimal("2.5"),
               detail_hrs: BigDecimal("0.75"))
      end

      it "creates a line item with the product's name as description when description is blank" do
        post estimate_line_items_path(estimate), params: {
          line_item: {
            product_id: product.id,
            description: "",
            quantity: "1",
            unit: "EA"
          }
        }
        expect(LineItem.last.description).to eq("MDF Base 2-door")
      end

      it "copies exterior_description from the product" do
        post estimate_line_items_path(estimate), params: {
          line_item: {
            product_id: product.id,
            description: "",
            quantity: "1",
            unit: "EA"
          }
        }
        expect(LineItem.last.exterior_description).to eq("MDF")
      end

      it "respects an overridden description param over the product name" do
        post estimate_line_items_path(estimate), params: {
          line_item: {
            product_id: product.id,
            description: "My custom override",
            quantity: "1",
            unit: "EA"
          }
        }
        expect(LineItem.last.description).to eq("My custom override")
      end

      it "sets product_id on the created line item" do
        post estimate_line_items_path(estimate), params: {
          line_item: {
            product_id: product.id,
            description: "",
            quantity: "1",
            unit: "EA"
          }
        }
        expect(LineItem.last.product_id).to eq(product.id)
      end
    end

    context "with invalid params" do
      it "returns unprocessable entity when description is blank" do
        post estimate_line_items_path(estimate), params: {
          line_item: { description: "", quantity: "1", unit: "EA" }
        }
        expect(response).to have_http_status(:unprocessable_content)
      end
    end

    it "redirects to login when unauthenticated" do
      delete session_path
      post estimate_line_items_path(estimate), params: {
        line_item: { description: "Test", quantity: "1", unit: "EA" }
      }
      expect(response).to redirect_to(new_session_path)
    end
  end

  describe "PATCH /estimates/:estimate_id/line_items/:id" do
    let!(:line_item) { create(:line_item, estimate: estimate, description: "Old Name") }

    it "updates the line item description" do
      patch estimate_line_item_path(estimate, line_item), params: {
        line_item: { description: "New Name", quantity: "1", unit: "EA" }
      }
      expect(line_item.reload.description).to eq("New Name")
    end

    it "redirects to the estimate edit page on success" do
      patch estimate_line_item_path(estimate, line_item), params: {
        line_item: { description: "New Name", quantity: "1", unit: "EA" }
      }
      expect(response).to redirect_to(edit_estimate_path(estimate))
    end
  end

  describe "DELETE /estimates/:estimate_id/line_items/:id" do
    let!(:line_item) { create(:line_item, estimate: estimate) }

    it "destroys the line item" do
      expect {
        delete estimate_line_item_path(estimate, line_item)
      }.to change(LineItem, :count).by(-1)
    end

    it "redirects to the estimate edit page" do
      delete estimate_line_item_path(estimate, line_item)
      expect(response).to redirect_to(edit_estimate_path(estimate))
    end
  end
end
