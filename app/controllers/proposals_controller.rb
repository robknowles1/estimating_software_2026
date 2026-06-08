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

  # Creation is instantaneous, so there is no intermediate form: new delegates
  # straight to create.
  def new
    create
  end

  # Resumes the wizard at the proposal's current (earliest incomplete) step.
  def show
    redirect_to step_estimate_proposal_path(@estimate, @estimate.proposal.current_step)
  end

  private

  def set_estimate
    @estimate = Estimate.find(params[:estimate_id])
  end
end
