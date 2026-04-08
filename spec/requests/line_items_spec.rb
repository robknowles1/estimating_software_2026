require "rails_helper"

RSpec.describe "LineItems", type: :request do
  let(:user) { create(:user) }
  let(:estimate) { create(:estimate, :skip_material_seeding, created_by: user) }
  let(:section) { create(:estimate_section, estimate: estimate, quantity: 5) }
  let(:material) do
    create(:estimate_material, estimate: estimate, category: "pl", slot_number: 1, price_per_unit: BigDecimal("50.00"))
  end
  let!(:assembly_rate) { create(:labor_rate, labor_category: "assembly", hourly_rate: BigDecimal("25.00")) }

  before { sign_in(user) }

  describe "POST /estimates/:estimate_id/estimate_sections/:id/line_items" do
    let(:valid_params) do
      {
        line_item: {
          description: "Exterior Sheet Good",
          line_item_category: "material",
          component_type: "exterior",
          estimate_material_id: material.id,
          component_quantity: "0.32"
        }
      }
    end

    it "creates the line item" do
      expect {
        post estimate_estimate_section_line_items_path(estimate, section),
          params: valid_params
      }.to change(LineItem, :count).by(1)
    end

    it "responds with Turbo Stream format including section subtotal and estimate totals" do
      post estimate_estimate_section_line_items_path(estimate, section),
        params: valid_params,
        headers: { "Accept" => "text/vnd.turbo-stream.html" }

      expect(response.content_type).to include("text/vnd.turbo-stream.html")
      expect(response.body).to include("subtotal_estimate_section_#{section.id}")
      expect(response.body).to include("totals_estimate_#{estimate.id}")
    end

    it "returns 422 when description is blank" do
      post estimate_estimate_section_line_items_path(estimate, section),
        params: { line_item: { description: "", line_item_category: "material" } }

      expect(response).to have_http_status(:unprocessable_content)
    end

    it "defaults line_item_category to material" do
      post estimate_estimate_section_line_items_path(estimate, section),
        params: { line_item: { description: "Test item" } }

      expect(LineItem.last.line_item_category).to eq("material")
    end

    it "pre-fills markup_percent from section default when not supplied (AC-11)" do
      section.update!(default_markup_percent: 15)

      post estimate_estimate_section_line_items_path(estimate, section),
        params: { line_item: { description: "Test item", line_item_category: "material" } }

      expect(LineItem.last.markup_percent).to eq(BigDecimal("15"))
    end
  end

  describe "PATCH /estimates/:estimate_id/estimate_sections/:id/line_items/:id" do
    let!(:line_item) do
      create(:line_item,
        estimate_section: section,
        line_item_category: "material",
        description: "Old Description",
        estimate_material: material,
        component_quantity: BigDecimal("0.32"))
    end

    it "updates the line item" do
      patch estimate_estimate_section_line_item_path(estimate, section, line_item),
        params: { line_item: { component_quantity: "0.64" } },
        headers: { "Accept" => "text/vnd.turbo-stream.html" }

      expect(line_item.reload.component_quantity).to eq(BigDecimal("0.64"))
    end

    it "responds with Turbo Stream including recalculated totals" do
      patch estimate_estimate_section_line_item_path(estimate, section, line_item),
        params: { line_item: { component_quantity: "0.64" } },
        headers: { "Accept" => "text/vnd.turbo-stream.html" }

      expect(response.content_type).to include("text/vnd.turbo-stream.html")
      expect(response.body).to include("subtotal_estimate_section_#{section.id}")
      expect(response.body).to include("totals_estimate_#{estimate.id}")
    end
  end

  describe "DELETE /estimates/:estimate_id/estimate_sections/:id/line_items/:id" do
    let!(:line_item) do
      create(:line_item,
        estimate_section: section,
        description: "To Delete",
        line_item_category: "material")
    end

    it "removes the line item" do
      expect {
        delete estimate_estimate_section_line_item_path(estimate, section, line_item),
          headers: { "Accept" => "text/vnd.turbo-stream.html" }
      }.to change(LineItem, :count).by(-1)
    end

    it "responds with Turbo Stream updating subtotal and grand total" do
      delete estimate_estimate_section_line_item_path(estimate, section, line_item),
        headers: { "Accept" => "text/vnd.turbo-stream.html" }

      expect(response.content_type).to include("text/vnd.turbo-stream.html")
      expect(response.body).to include("subtotal_estimate_section_#{section.id}")
      expect(response.body).to include("totals_estimate_#{estimate.id}")
    end
  end

  describe "PATCH /estimates/:estimate_id/estimate_sections/:id/line_items/:id/move" do
    let!(:first_item) do
      create(:line_item, estimate_section: section, description: "First", line_item_category: "material")
    end
    let!(:second_item) do
      create(:line_item, estimate_section: section, description: "Second", line_item_category: "material")
    end

    it "decrements position when direction is up" do
      original_pos = second_item.position

      patch move_estimate_estimate_section_line_item_path(estimate, section, second_item),
        params: { direction: "up" }

      expect(second_item.reload.position).to be < original_pos
    end

    it "redirects to estimate edit" do
      patch move_estimate_estimate_section_line_item_path(estimate, section, second_item),
        params: { direction: "up" }

      expect(response).to redirect_to(edit_estimate_path(estimate))
    end
  end
end
