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

  describe "GET /estimates/:estimate_id/proposal/new" do
    before { sign_in(user) }

    it "does not create a proposal (side-effect-free GET) and redirects to the estimate page" do
      expect {
        get new_estimate_proposal_path(estimate)
      }.not_to change(Proposal, :count)

      expect(response).to redirect_to(edit_estimate_path(estimate))
    end

    it "resumes an existing proposal without creating a duplicate" do
      proposal = Proposals::BuildService.new(estimate: estimate).call

      expect {
        get new_estimate_proposal_path(estimate)
      }.not_to change(Proposal, :count)

      expect(response).to redirect_to(step_estimate_proposal_path(estimate, proposal.current_step))
    end
  end

  describe "GET /estimates/:estimate_id/proposal" do
    before { sign_in(user) }

    context "when a proposal exists" do
      it "redirects to the proposal's current step" do
        proposal = Proposals::BuildService.new(estimate: estimate).call
        get estimate_proposal_path(estimate)
        expect(response).to redirect_to(step_estimate_proposal_path(estimate, proposal.current_step))
      end
    end

    context "when no proposal exists" do
      it "redirects to the estimate page without 500ing or creating anything" do
        expect {
          get estimate_proposal_path(estimate)
        }.not_to change(Proposal, :count)

        expect(response).to have_http_status(:redirect)
        expect(response).to redirect_to(edit_estimate_path(estimate))
      end
    end
  end

  describe "GET /estimates/:estimate_id/proposal/steps/:step (unauthenticated)" do
    before { Proposals::BuildService.new(estimate: estimate).call }

    it "redirects to the login page" do
      get step_estimate_proposal_path(estimate, "opening")
      expect(response).to redirect_to(new_session_path)
    end
  end

  describe "GET /estimates/:estimate_id/proposal/pdf" do
    before { Proposals::BuildService.new(estimate: estimate).call }

    context "when authenticated" do
      before { sign_in(user) }

      # AT13 — the response is application/pdf with a body starting with %PDF.
      it "serves the PDF as a download" do
        get pdf_estimate_proposal_path(estimate)

        expect(response).to have_http_status(:ok)
        expect(response.media_type).to eq("application/pdf")
        expect(response.body).to start_with("%PDF")
        expect(response.headers["Content-Disposition"]).to include("attachment")
        expect(response.headers["Content-Disposition"]).to include("proposal-#{estimate.estimate_number}.pdf")
      end

      # E8 — a render failure redirects to the review step with an error flash and
      # serves no partial PDF.
      it "redirects to the review step with an error flash when rendering fails" do
        service = instance_double(Proposals::PdfRenderService)
        allow(Proposals::PdfRenderService).to receive(:new).and_return(service)
        allow(service).to receive(:call).and_raise(StandardError, "boom")

        get pdf_estimate_proposal_path(estimate)

        expect(response).to redirect_to(step_estimate_proposal_path(estimate, "review"))
        expect(flash[:alert]).to eq(I18n.t("proposals.steps.review.pdf_error"))
      end
    end

    context "when unauthenticated" do
      it "redirects to the login page" do
        get pdf_estimate_proposal_path(estimate)
        expect(response).to redirect_to(new_session_path)
      end
    end
  end

  describe "POST /estimates/:estimate_id/proposal/email" do
    let!(:proposal) do
      Proposals::BuildService.new(estimate: estimate).call.tap do |p|
        p.update!(current_step: "review")
      end
    end

    before { ActionMailer::Base.deliveries.clear }

    context "when authenticated" do
      before { sign_in(user) }

      # AC-25 / AC-34 — a valid address sends one email, flips proposal and
      # estimate status to sent, and redirects to the review step with a notice.
      it "sends the proposal email, marks it sent, and redirects with a notice" do
        expect {
          post email_estimate_proposal_path(estimate), params: { recipient_email: "client@example.com" }
        }.to change { ActionMailer::Base.deliveries.size }.by(1)

        expect(proposal.reload.status).to eq("sent")
        expect(estimate.reload.status).to eq("sent")
        expect(response).to redirect_to(step_estimate_proposal_path(estimate, "review"))
        expect(flash[:notice]).to eq(
          I18n.t("proposals.steps.review.email_notice", email: "client@example.com")
        )
      end

      # AT15 / E9 / AC-26 — a blank address returns 422, sends nothing, and
      # leaves the status unchanged.
      it "returns 422 and sends nothing when the recipient is blank" do
        expect {
          post email_estimate_proposal_path(estimate), params: { recipient_email: "" }
        }.not_to change { ActionMailer::Base.deliveries.size }

        expect(response).to have_http_status(:unprocessable_content)
        expect(proposal.reload.status).to eq("draft")
      end

      # An invalid-but-non-blank address returns 422 and the typed value is
      # preserved in the recipient field so the user can correct it in place
      # (rather than the field resetting to the contact default).
      it "returns 422 and preserves the typed recipient when the address is invalid" do
        expect {
          post email_estimate_proposal_path(estimate), params: { recipient_email: "not-an-email" }
        }.not_to change { ActionMailer::Base.deliveries.size }

        expect(response).to have_http_status(:unprocessable_content)
        expect(proposal.reload.status).to eq("draft")
        expect(response.body).to include('value="not-an-email"')
      end

      # Header-injection guard — a CRLF/extra-recipient address is rejected with
      # a 422 and no send.
      it "returns 422 and sends nothing for a header-injection address" do
        expect {
          post email_estimate_proposal_path(estimate),
               params: { recipient_email: "a@b.com\nBcc: evil@x.com" }
        }.not_to change { ActionMailer::Base.deliveries.size }

        expect(response).to have_http_status(:unprocessable_content)
        expect(proposal.reload.status).to eq("draft")
      end

      # The email is already sent when the status update fails. We must not claim a
      # clean success: redirect with an honest alert (email sent, status not
      # updated) and 302, not a 500. The delivery still happened (count + 1).
      it "redirects with an honest alert when the email sent but the status update fails" do
        allow_any_instance_of(Proposal).to receive(:update).with(status: :sent).and_return(false)

        expect {
          post email_estimate_proposal_path(estimate), params: { recipient_email: "client@example.com" }
        }.to change { ActionMailer::Base.deliveries.size }.by(1)

        expect(response).to redirect_to(step_estimate_proposal_path(estimate, "review"))
        expect(flash[:alert]).to eq(
          I18n.t("proposals.steps.review.email_sent_status_error", email: "client@example.com")
        )
        # The action sets no success notice on this branch (it does not claim a
        # clean success); the only notice present is the leftover sign-in flash.
        expect(flash[:notice]).not_to eq(
          I18n.t("proposals.steps.review.email_notice", email: "client@example.com")
        )
      end

      # A delivery failure re-renders the review step with an error flash (no 500).
      it "re-renders the review step with an error when delivery fails" do
        service = instance_double(Proposals::EmailDeliveryService)
        allow(Proposals::EmailDeliveryService).to receive(:new).and_return(service)
        allow(service).to receive(:call).and_return(
          Proposals::EmailDeliveryService::Result.new(success: false, error: "boom")
        )

        post email_estimate_proposal_path(estimate), params: { recipient_email: "client@example.com" }

        expect(response).to have_http_status(:unprocessable_content)
        expect(proposal.reload.status).to eq("draft")
        expect(flash[:alert]).to eq(I18n.t("proposals.steps.review.email_error"))
      end
    end

    context "when the proposal has not reached the review step" do
      before { sign_in(user) }

      # email is a review-step action (R15); a crafted POST against an incomplete
      # proposal must not send. The guard mirrors the wizard's future-step
      # behavior: redirect to the current step with the future-step notice, send
      # nothing, leave the status unchanged.
      it "redirects to the current step with the future-step notice and sends nothing" do
        proposal.update!(current_step: "opening")

        expect {
          post email_estimate_proposal_path(estimate), params: { recipient_email: "client@example.com" }
        }.not_to change { ActionMailer::Base.deliveries.size }

        expect(response).to redirect_to(step_estimate_proposal_path(estimate, "opening"))
        expect(flash[:notice]).to eq(I18n.t("proposals.steps.show.future_step_notice"))
        expect(proposal.reload.status).to eq("draft")
      end
    end

    context "when unauthenticated" do
      it "redirects to login and sends nothing" do
        expect {
          post email_estimate_proposal_path(estimate), params: { recipient_email: "client@example.com" }
        }.not_to change { ActionMailer::Base.deliveries.size }

        expect(response).to redirect_to(new_session_path)
      end
    end
  end

  describe "POST /estimates/:estimate_id/proposal/mark_as_sent" do
    let!(:proposal) do
      Proposals::BuildService.new(estimate: estimate).call.tap do |p|
        p.update!(current_step: "review")
      end
    end

    context "when authenticated" do
      before { sign_in(user) }

      # AC-34 — Mark as Sent flips proposal and estimate status to sent, then
      # returns the user to the estimate page.
      it "marks the proposal sent and redirects to the estimate" do
        post mark_as_sent_estimate_proposal_path(estimate)

        expect(proposal.reload.status).to eq("sent")
        expect(estimate.reload.status).to eq("sent")
        expect(response).to redirect_to(edit_estimate_path(estimate))
        expect(flash[:notice]).to eq(I18n.t("proposals.steps.review.mark_as_sent_notice"))
      end

      # When the status update fails, redirect with an error alert (no false
      # success notice, no 500).
      it "redirects with an error alert when the status update fails" do
        allow_any_instance_of(Proposal).to receive(:update).with(status: :sent).and_return(false)

        post mark_as_sent_estimate_proposal_path(estimate)

        expect(response).to redirect_to(step_estimate_proposal_path(estimate, "review"))
        expect(flash[:alert]).to eq(I18n.t("proposals.steps.review.mark_as_sent_error"))
        # The action sets no success notice on this branch; any notice present is
        # the leftover sign-in flash, never the mark-as-sent success notice.
        expect(flash[:notice]).not_to eq(I18n.t("proposals.steps.review.mark_as_sent_notice"))
      end
    end

    context "when the proposal has not reached the review step" do
      before { sign_in(user) }

      # mark_as_sent is a review-step action (R15); a crafted POST against an
      # incomplete proposal must not flip the status. The guard redirects to the
      # current step with the future-step notice and leaves the status unchanged.
      it "redirects to the current step with the future-step notice and does not change status" do
        proposal.update!(current_step: "opening")

        post mark_as_sent_estimate_proposal_path(estimate)

        expect(response).to redirect_to(step_estimate_proposal_path(estimate, "opening"))
        expect(flash[:notice]).to eq(I18n.t("proposals.steps.show.future_step_notice"))
        expect(proposal.reload.status).to eq("draft")
      end
    end

    context "when unauthenticated" do
      it "redirects to login and does not change status" do
        post mark_as_sent_estimate_proposal_path(estimate)

        expect(response).to redirect_to(new_session_path)
        expect(proposal.reload.status).to eq("draft")
      end
    end
  end
end
