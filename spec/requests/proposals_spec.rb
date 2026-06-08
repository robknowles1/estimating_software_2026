require "rails_helper"

RSpec.describe "Proposals", type: :request do
  let(:user)     { create(:user) }
  let(:client)   { create(:client) }
  let(:estimate) { create(:estimate, client: client) }

  describe "POST /estimates/:estimate_id/proposal" do
    context "when authenticated and no proposal exists" do
      before { sign_in(user) }

      it "creates a proposal and redirects to the opening step" do
        expect {
          post estimate_proposal_path(estimate)
        }.to change(Proposal, :count).by(1)

        proposal = estimate.reload.proposal
        expect(proposal.mode).to eq("commercial")
        expect(proposal.status).to eq("draft")
        expect(response).to redirect_to(step_estimate_proposal_path(estimate, "opening"))
      end
    end

    context "when a proposal already exists" do
      before do
        sign_in(user)
        Proposals::BuildService.new(estimate: estimate).call
      end

      it "does not create a duplicate and redirects to the current step" do
        expect {
          post estimate_proposal_path(estimate)
        }.not_to change(Proposal, :count)

        expect(response).to redirect_to(
          step_estimate_proposal_path(estimate, estimate.reload.proposal.current_step)
        )
      end
    end

    context "when unauthenticated" do
      it "redirects to the login page and creates nothing" do
        expect {
          post estimate_proposal_path(estimate)
        }.not_to change(Proposal, :count)

        expect(response).to redirect_to(new_session_path)
      end
    end
  end

  describe "GET /estimates/:estimate_id/proposal" do
    before do
      sign_in(user)
      @proposal = Proposals::BuildService.new(estimate: estimate).call
    end

    it "redirects to the proposal's current step" do
      get estimate_proposal_path(estimate)
      expect(response).to redirect_to(step_estimate_proposal_path(estimate, @proposal.current_step))
    end
  end

  describe "GET /estimates/:estimate_id/proposal/steps/:step (unauthenticated)" do
    before { Proposals::BuildService.new(estimate: estimate).call }

    it "redirects to the login page" do
      get step_estimate_proposal_path(estimate, "opening")
      expect(response).to redirect_to(new_session_path)
    end
  end
end
