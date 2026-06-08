require "rails_helper"

RSpec.describe "Proposals::Steps", type: :request do
  let(:user)     { create(:user) }
  let(:client)   { create(:client) }
  let(:estimate) { create(:estimate, client: client) }
  let!(:contact) { create(:contact, client: client, is_primary: true) }
  let!(:proposal) { Proposals::BuildService.new(estimate: estimate).call }

  before { sign_in(user) }

  describe "PATCH .../steps/opening" do
    it "saves and advances to specifications in commercial mode" do
      patch step_estimate_proposal_path(estimate, "opening"), params: {
        proposal: { contact_id: contact.id, job_name: "Acme HQ", mode: "commercial", total_amount: "1000.00" }
      }

      expect(response).to redirect_to(step_estimate_proposal_path(estimate, "specifications"))
      expect(proposal.reload.current_step).to eq("specifications")
      expect(proposal.job_name).to eq("Acme HQ")
    end

    it "saves and advances to inclusions in residential mode" do
      patch step_estimate_proposal_path(estimate, "opening"), params: {
        proposal: { contact_id: contact.id, job_name: "Home", mode: "residential", total_amount: "1000.00" }
      }

      expect(response).to redirect_to(step_estimate_proposal_path(estimate, "inclusions"))
      expect(proposal.reload.current_step).to eq("inclusions")
    end

    it "returns 422 when no contact is selected" do
      # Contact is required at the form layer; submitting blank re-renders 422.
      patch step_estimate_proposal_path(estimate, "opening"), params: {
        proposal: { contact_id: "", job_name: "Acme HQ", mode: "commercial" }
      }

      expect(response).to have_http_status(:unprocessable_content)
      expect(proposal.reload.current_step).to eq("opening")
    end
  end

  describe "GET .../steps/:step future-step guard" do
    it "redirects to the earliest incomplete step with a flash" do
      # Fresh proposal: current_step == opening. Visiting alternates is ahead.
      get step_estimate_proposal_path(estimate, "alternates")

      expect(response).to redirect_to(step_estimate_proposal_path(estimate, "opening"))
      expect(flash[:notice]).to be_present
    end
  end

  describe "PATCH .../steps/:step future-step guard (M1)" do
    it "redirects a PATCH to a future step without advancing or persisting" do
      # Fresh proposal: current_step == opening. A direct PATCH to clarifications
      # (a future step) must be guarded just like a GET — no save, no advance.
      existing_bodies = proposal.proposal_clarifications.pluck(:body)

      patch step_estimate_proposal_path(estimate, "clarifications"), params: {
        proposal: {
          proposal_clarifications_attributes: {
            "0" => { body: "Injected future-step clarification" }
          }
        }
      }

      expect(response).to redirect_to(step_estimate_proposal_path(estimate, "opening"))
      expect(flash[:notice]).to be_present
      expect(proposal.reload.current_step).to eq("opening")
      expect(proposal.proposal_clarifications.pluck(:body)).to match_array(existing_bodies)
    end
  end

  describe "GET .../steps/specifications in residential mode" do
    it "redirects to inclusions" do
      proposal.update!(mode: "residential")
      get step_estimate_proposal_path(estimate, "specifications")
      expect(response).to redirect_to(step_estimate_proposal_path(estimate, "inclusions"))
    end
  end

  describe "PATCH .../steps/clarifications" do
    it "saves clarifications and advances" do
      # Advance to clarifications first so the guard allows the save target.
      proposal.update!(current_step: "clarifications")
      existing = proposal.proposal_clarifications.first

      patch step_estimate_proposal_path(estimate, "clarifications"), params: {
        proposal: {
          proposal_clarifications_attributes: {
            "0" => { id: existing.id, body: existing.body },
            "1" => { body: "Custom clarification" }
          }
        }
      }

      expect(response).to redirect_to(step_estimate_proposal_path(estimate, "alternates"))
      expect(proposal.reload.proposal_clarifications.pluck(:body)).to include("Custom clarification")
    end
  end

  describe "PATCH .../steps/alternates (AT11)" do
    # A separate estimate carrying an alternate line item so BuildService seeds a
    # ProposalAlternate to edit. The top-level estimate has no line items.
    let(:alt_estimate) { create(:estimate, client: client) }
    let!(:alt_line_item) do
      create(:line_item, estimate: alt_estimate, description: "ALT-1 Painted Finish")
    end
    let!(:alt_proposal) { Proposals::BuildService.new(estimate: alt_estimate).call }

    it "persists an edited display_cost and advances to exclusions" do
      alt_proposal.update!(current_step: "alternates")
      alternate = alt_proposal.proposal_alternates.first
      expect(alternate).to be_present

      patch step_estimate_proposal_path(alt_estimate, "alternates"), params: {
        proposal: {
          proposal_alternates_attributes: {
            "0" => { id: alternate.id, display_cost: "1234.56" }
          }
        }
      }

      expect(response).to redirect_to(step_estimate_proposal_path(alt_estimate, "exclusions"))
      expect(alt_proposal.reload.current_step).to eq("exclusions")
      expect(alternate.reload.display_cost).to eq(BigDecimal("1234.56"))
    end
  end

  describe "GET .../steps/clarifications (AT9)" do
    it "renders the two standard R11 clarification rows" do
      proposal.update!(current_step: "clarifications")
      get step_estimate_proposal_path(estimate, "clarifications")

      expect(response).to have_http_status(:ok)
      Proposals::BuildService::STANDARD_CLARIFICATIONS.each do |body|
        expect(response.body).to include(ERB::Util.html_escape(body))
      end

      # Two persisted rows render (the NEW_RECORD <template> row is excluded).
      rendered = Nokogiri::HTML(response.body)
      rows = rendered.css(
        "textarea[name^='proposal[proposal_clarifications_attributes]']"
      ).reject { |t| t["name"].include?("NEW_RECORD") }
      expect(rows.size).to eq(2)
    end
  end

  describe "GET .../steps/exclusions (AT12)" do
    it "renders the thirteen standard R14 exclusion rows" do
      proposal.update!(current_step: "exclusions")
      get step_estimate_proposal_path(estimate, "exclusions")

      expect(response).to have_http_status(:ok)
      Proposals::BuildService::STANDARD_EXCLUSIONS.each do |body|
        expect(response.body).to include(ERB::Util.html_escape(body))
      end

      rendered = Nokogiri::HTML(response.body)
      rows = rendered.css(
        "textarea[name^='proposal[proposal_exclusions_attributes]']"
      ).reject { |t| t["name"].include?("NEW_RECORD") }
      expect(rows.size).to eq(13)
    end
  end

  describe "PATCH .../steps/inclusions with an invalid photo" do
    let(:bad_file) do
      Rack::Test::UploadedFile.new(
        Rails.root.join("spec/fixtures/files/sample_import.csv"), "text/csv"
      )
    end

    it "returns 422, stores nothing, and does not advance" do
      proposal.update!(current_step: "inclusions")
      proposal.proposal_inclusions.create!(room_name: "Kitchen")
      inclusion = proposal.proposal_inclusions.first

      expect {
        patch step_estimate_proposal_path(estimate, "inclusions"), params: {
          proposal: {
            proposal_inclusions_attributes: {
              "0" => { id: inclusion.id, room_name: "Kitchen", photos: [ bad_file ] }
            }
          }
        }
      }.not_to change { ActiveStorage::Attachment.count }

      expect(response).to have_http_status(:unprocessable_content)
      expect(proposal.reload.current_step).to eq("inclusions")
    end
  end
end
