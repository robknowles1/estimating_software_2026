class ProposalsController < ApplicationController
  before_action :set_estimate

  # Creates the proposal for the estimate (one per estimate). If one already
  # exists, redirects to its current step without creating a duplicate (R1, E10).
  def create
    if @estimate.proposal.present?
      redirect_to step_estimate_proposal_path(@estimate, @estimate.proposal.current_step),
                  notice: t("proposals.create.already_exists")
      return
    end

    proposal = Proposals::BuildService.new(estimate: @estimate).call
    redirect_to step_estimate_proposal_path(@estimate, proposal.current_step),
                notice: t("proposals.create.notice")
  end

  # Side-effect-free GET. Creation happens only via POST to create, so new
  # carries no side effect: if a proposal already exists, resume it; otherwise
  # send the user to the estimate page where the POST "Create Proposal" button
  # lives. This is also the landing target StepsController uses when a proposal
  # is missing, so the flow never dead-ends.
  def new
    if @estimate.proposal.present?
      redirect_to step_estimate_proposal_path(@estimate, @estimate.proposal.current_step)
    else
      redirect_to edit_estimate_path(@estimate)
    end
  end

  # Resumes the wizard at the proposal's current (earliest incomplete) step. If
  # no proposal exists yet (E10), redirect to the estimate page's create entry
  # point rather than 500 on nil.current_step.
  def show
    redirect_to edit_estimate_path(@estimate) and return if @estimate.proposal.nil?

    redirect_to step_estimate_proposal_path(@estimate, @estimate.proposal.current_step)
  end

  # Generates the proposal PDF on demand (R16) and serves it as a download. The
  # filename interpolates the app-generated estimate_number (never user input).
  # On any render failure (E8) the error is logged and the user is returned to
  # the review step with an error flash; no partial PDF is served.
  def pdf
    @proposal = @estimate.proposal
    redirect_to edit_estimate_path(@estimate) and return if @proposal.nil?

    pdf = Proposals::PdfRenderService.new(proposal: @proposal).call
    send_data pdf,
              filename: "proposal-#{@estimate.estimate_number}.pdf",
              type: "application/pdf",
              disposition: :attachment
  rescue StandardError => e
    Rails.logger.error("[ProposalsController#pdf] #{e.class}: #{e.message}")
    redirect_to step_estimate_proposal_path(@estimate, "review"),
                alert: t("proposals.steps.review.pdf_error")
  end

  private

  def set_estimate
    @estimate = Estimate.find(params[:estimate_id])
  end
end
