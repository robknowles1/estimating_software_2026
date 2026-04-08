require "rails_helper"

RSpec.describe "EstimateSections", type: :request do
  let(:user) { create(:user) }
  let(:client) { create(:client) }
  let(:estimate) { create(:estimate, client: client, created_by: user) }

  before { sign_in(user) }

  describe "POST /estimates/:estimate_id/estimate_sections" do
    let(:valid_params) do
      { estimate_section: { name: "Cabinets", default_markup_percent: 15.0 } }
    end

    context "with valid params" do
      it "creates a section and redirects to estimate edit" do
        expect {
          post estimate_estimate_sections_path(estimate), params: valid_params
        }.to change(EstimateSection, :count).by(1)

        expect(response).to redirect_to(edit_estimate_path(estimate))
      end

      it "the new section appears on the estimate edit page" do
        post estimate_estimate_sections_path(estimate), params: valid_params
        follow_redirect!
        expect(response.body).to include("Cabinets")
      end
    end

    context "without a name" do
      it "returns unprocessable entity" do
        post estimate_estimate_sections_path(estimate), params: { estimate_section: { name: "" } }
        expect(response).to have_http_status(:unprocessable_content)
      end

      it "does not create a section" do
        expect {
          post estimate_estimate_sections_path(estimate), params: { estimate_section: { name: "" } }
        }.not_to change(EstimateSection, :count)
      end
    end
  end

  describe "PATCH /estimates/:estimate_id/estimate_sections/:id/move" do
    let!(:first_section)  { create(:estimate_section, estimate: estimate, name: "First") }
    let!(:second_section) { create(:estimate_section, estimate: estimate, name: "Second") }

    it "decrements position when direction is up" do
      original_pos = second_section.position

      patch move_estimate_estimate_section_path(estimate, second_section), params: { direction: "up" }

      expect(second_section.reload.position).to be < original_pos
    end

    it "redirects to estimate edit page" do
      patch move_estimate_estimate_section_path(estimate, second_section), params: { direction: "up" }
      expect(response).to redirect_to(edit_estimate_path(estimate))
    end

    it "increments position when direction is down" do
      original_pos = first_section.position

      patch move_estimate_estimate_section_path(estimate, first_section), params: { direction: "down" }

      expect(first_section.reload.position).to be > original_pos
    end
  end

  describe "DELETE /estimates/:estimate_id/estimate_sections/:id" do
    let!(:section) { create(:estimate_section, estimate: estimate) }

    it "destroys the section and redirects to estimate edit" do
      expect {
        delete estimate_estimate_section_path(estimate, section)
      }.to change(EstimateSection, :count).by(-1)

      expect(response).to redirect_to(edit_estimate_path(estimate))
    end
  end
end
