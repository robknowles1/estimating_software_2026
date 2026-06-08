module Proposals
  # Drives the proposal wizard's per-step show/update flow. Step completeness is
  # tracked solely via Proposal#current_step (R4): a step is "complete" when it
  # appears before current_step in the (mode-adjusted) step order. status never
  # gates editing.
  class StepsController < ApplicationController
    before_action :set_estimate_and_proposal
    before_action :set_step
    before_action :redirect_skipped_specifications
    before_action :guard_future_step, only: %i[show update]

    # Maps each whitelisted step to its save method. Built from Proposal::STEPS so
    # the wizard's step list and the dispatch table cannot drift apart. @step is
    # validated against this same whitelist in set_step before any lookup.
    STEP_SAVE_METHODS = Proposal::STEPS.to_h { |step| [ step, :"save_#{step}" ] }.freeze

    def show
      build_step_records
      render step_template
    end

    def update
      if save_step
        advance_current_step
        redirect_to step_estimate_proposal_path(@estimate, next_step(@step)), notice: t(".notice")
      else
        build_step_records
        render step_template, status: :unprocessable_content
      end
    end

    private

    def set_estimate_and_proposal
      @estimate = Estimate.find(params[:estimate_id])
      @proposal = @estimate.proposal
      redirect_to new_estimate_proposal_path(@estimate) and return if @proposal.nil?

      # A8: the review preview renders every association; eager-load them here to
      # avoid the N+1 when on that step. Other steps build their own records.
      if params[:step] == "review"
        @proposal = Proposal
                    .includes(:contact, :proposal_inclusions, :proposal_clarifications,
                              :proposal_alternates, :proposal_exclusions)
                    .find(@proposal.id)
      end
    end

    def set_step
      @step = params[:step]
      redirect_to step_estimate_proposal_path(@estimate, "opening") and return unless Proposal::STEPS.include?(@step)
    end

    # Residential proposals skip the specifications step entirely (R7).
    def redirect_skipped_specifications
      return unless @proposal.residential? && @step == "specifications"

      redirect_to step_estimate_proposal_path(@estimate, "inclusions")
    end

    # E7 / AT16: visiting a step ahead of current_step (when earlier steps are
    # incomplete) redirects to the earliest incomplete step.
    def guard_future_step
      return if step_index(@step) <= step_index(@proposal.current_step)

      redirect_to step_estimate_proposal_path(@estimate, @proposal.current_step),
                  notice: t(".future_step_notice")
    end

    # ----- step ordering (mode-aware) ----------------------------------------

    # Ordered list of steps for this proposal's mode (residential drops specs).
    def ordered_steps
      return Proposal::STEPS unless @proposal.residential?

      Proposal::STEPS - %w[specifications]
    end

    def step_index(step)
      ordered_steps.index(step) || 0
    end

    def next_step(step)
      # A9: "review" is the terminal step — when called on the last step the
      # `+ 1` index is out of range and we fall back to "review" itself, so a
      # save on review redirects back to review rather than off the end.
      ordered_steps[step_index(step) + 1] || "review"
    end

    # Advances current_step to the next step only when moving forward (never
    # rewinds progress when re-saving an earlier step).
    def advance_current_step
      target = next_step(@step)
      return unless step_index(target) > step_index(@proposal.current_step)

      @proposal.update!(current_step: target)
    end

    # ----- per-step records for rendering ------------------------------------

    def build_step_records
      case @step
      when "inclusions"
        @proposal.proposal_inclusions.build(room_name: "") if @proposal.proposal_inclusions.empty?
      when "clarifications"
        @proposal.proposal_clarifications.build if @proposal.proposal_clarifications.empty?
      when "exclusions"
        @proposal.proposal_exclusions.build if @proposal.proposal_exclusions.empty?
      when "specifications"
        @proposal.proposal_specifications.build if @proposal.proposal_specifications.empty?
      end
    end

    # ----- per-step save -----------------------------------------------------

    # @step is provably one of Proposal::STEPS (set_step halts otherwise), so the
    # dispatch table always resolves to a defined save_* method — no raw send on a
    # user-supplied param.
    def save_step
      send(STEP_SAVE_METHODS.fetch(@step))
    end

    # Template path for the current step. @step is whitelisted in set_step, so the
    # rendered partial can never be user-controlled.
    def step_template
      "proposals/steps/#{@step}"
    end

    def save_opening
      @proposal.assign_attributes(opening_params)
      @proposal.validating_opening = true
      @proposal.save
    end

    def save_specifications
      @proposal.assign_attributes(specifications_params)
      @proposal.save
    end

    def save_inclusions
      @proposal.assign_attributes(inclusions_params)
      @proposal.save
    end

    def save_clarifications
      @proposal.assign_attributes(clarifications_params)
      @proposal.save
    end

    def save_alternates
      @proposal.assign_attributes(alternates_params)
      @proposal.save
    end

    def save_exclusions
      @proposal.assign_attributes(exclusions_params)
      @proposal.save
    end

    def save_review
      true
    end

    # ----- strong params per step --------------------------------------------

    def opening_params
      permitted = [ :contact_id, :job_name, :plan_date, :addendum_list, :total_amount, :mode ]
      permitted << :payment_terms
      params.require(:proposal).permit(*permitted)
    end

    def specifications_params
      params.require(:proposal).permit(
        :include_specifications,
        proposal_specifications_attributes: [ :id, :spec_number, :spec_title, :_destroy ]
      )
    end

    def inclusions_params
      params.require(:proposal).permit(
        proposal_inclusions_attributes: [ :id, :room_name, :bullet_points, :_destroy, { photos: [] } ]
      )
    end

    def clarifications_params
      params.require(:proposal).permit(
        proposal_clarifications_attributes: [ :id, :body, :_destroy ]
      )
    end

    def alternates_params
      params.require(:proposal).permit(
        proposal_alternates_attributes: [ :id, :display_cost ]
      )
    end

    def exclusions_params
      params.require(:proposal).permit(
        proposal_exclusions_attributes: [ :id, :body, :_destroy ]
      )
    end
  end
end
