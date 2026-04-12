require "rails_helper"

RSpec.describe "LineItems", type: :request do
  let(:user)     { create(:user) }
  let(:estimate) { create(:estimate, :skip_material_seeding, created_by: user) }

  before { post session_path, params: { email: user.email, password: "password123" } }

  describe "POST /estimates/:estimate_id/line_items" do
    context "with valid params" do
      it "creates a line item and responds with Turbo Stream" do
        post estimate_line_items_path(estimate),
             params: { line_item: { description: "Base Cabinet", quantity: 2, unit: "ea" } },
             headers: { "Accept" => "text/vnd.turbo-stream.html" }

        expect(response).to have_http_status(:ok)
        expect(response.media_type).to eq("text/vnd.turbo-stream.html")
        expect(LineItem.count).to eq(1)
      end
    end

    context "without description" do
      it "returns 422 and Turbo Stream with errors" do
        post estimate_line_items_path(estimate),
             params: { line_item: { description: "", quantity: 1, unit: "ea" } },
             headers: { "Accept" => "text/vnd.turbo-stream.html" }

        expect(response).to have_http_status(:unprocessable_entity)
        expect(LineItem.count).to eq(0)
      end
    end
  end

  describe "PATCH /estimates/:estimate_id/line_items/:id" do
    let!(:line_item) { create(:line_item, estimate: estimate) }

    it "updates and responds with Turbo Stream" do
      patch estimate_line_item_path(estimate, line_item),
            params: { line_item: { quantity: 5, unit: "ea", description: line_item.description } },
            headers: { "Accept" => "text/vnd.turbo-stream.html" }

      expect(response).to have_http_status(:ok)
      expect(line_item.reload.quantity).to eq(BigDecimal("5"))
    end
  end

  describe "DELETE /estimates/:estimate_id/line_items/:id" do
    let!(:line_item) { create(:line_item, estimate: estimate) }

    it "destroys and responds with Turbo Stream" do
      delete estimate_line_item_path(estimate, line_item),
             headers: { "Accept" => "text/vnd.turbo-stream.html" }

      expect(response).to have_http_status(:ok)
      expect(LineItem.count).to eq(0)
    end
  end

  describe "PATCH /estimates/:estimate_id/line_items/:id/move" do
    let!(:li1) { create(:line_item, estimate: estimate) }
    let!(:li2) { create(:line_item, estimate: estimate) }

    it "moves line item up" do
      expect(li2.position).to be > li1.position
      patch move_estimate_line_item_path(estimate, li2), params: { direction: "up" }
      expect(response).to redirect_to(edit_estimate_path(estimate))
      expect(li2.reload.position).to be < li1.reload.position
    end
  end
end
