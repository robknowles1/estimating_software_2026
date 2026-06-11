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

  # Emails the proposal PDF to a recipient (R15 / AC-25). The recipient address
  # comes straight from params and is passed only to EmailDeliveryService, which
  # validates it (format + header-injection guard) before any mailer work.
  #
  # On success the status moves to sent (R25 / AC-34) and we redirect to the
  # review step with a notice. A delivery failure re-renders the review step with
  # an error flash (no 500). A blank/invalid/injection address raises
  # ArgumentError from the service and is rendered as a 422 with no email sent
  # (E9 / AT15 / AC-26).
  def email
    @proposal = @estimate.proposal
    redirect_to edit_estimate_path(@estimate) and return if @proposal.nil?

    recipient = params[:recipient_email]
    result = Proposals::EmailDeliveryService.new(proposal: @proposal, recipient_email: recipient).call

    if result.success
      # The email is already sent at this point. If the status update fails we
      # must not lose that fact: surface a flash that says the email went out but
      # the status couldn't be updated (and log it) rather than claiming a clean
      # success or pretending nothing happened.
      if @proposal.update(status: :sent)
        redirect_to step_estimate_proposal_path(@estimate, "review"),
                    notice: t("proposals.steps.review.email_notice", email: recipient)
      else
        Rails.logger.error(
          "[ProposalsController#email] email sent to #{recipient} but status update " \
          "failed for proposal #{@proposal.id}: #{@proposal.errors.full_messages.join(', ')}"
        )
        redirect_to step_estimate_proposal_path(@estimate, "review"),
                    alert: t("proposals.steps.review.email_sent_status_error", email: recipient)
      end
    else
      render_review_with_email_error(t("proposals.steps.review.email_error"))
    end
  rescue ArgumentError
    render_review_with_email_error(t("proposals.steps.review.email_error"))
  end

  # Records that the proposal was delivered by other means without sending an
  # email (R15 / R25 / AC-34). Status never gates editing.
  def mark_as_sent
    @proposal = @estimate.proposal
    redirect_to edit_estimate_path(@estimate) and return if @proposal.nil?

    if @proposal.update(status: :sent)
      redirect_to step_estimate_proposal_path(@estimate, "review"),
                  notice: t("proposals.steps.review.mark_as_sent_notice")
    else
      redirect_to step_estimate_proposal_path(@estimate, "review"),
                  alert: t("proposals.steps.review.mark_as_sent_error")
    end
  end

  private

  def set_estimate
    @estimate = Estimate.find(params[:estimate_id])
  end

  # Re-render the review step (with all associations eager-loaded as the preview
  # reads them) and a 422 so a blank/invalid address surfaces inline on the
  # review form — AT15 requires the 422 status.
  def render_review_with_email_error(message)
    @proposal = Proposal
                .includes(:contact, :proposal_clarifications, :proposal_alternates,
                          :proposal_exclusions, :proposal_specifications,
                          proposal_inclusions: { photos_attachments: :blob })
                .find(@proposal.id)
    @step = "review"
    flash.now[:alert] = message
    render "proposals/steps/review", status: :unprocessable_content
  end
end
