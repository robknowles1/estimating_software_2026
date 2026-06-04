module Proposals
  # Creates a new Proposal for an estimate and seeds its child records:
  # standard clarifications (R11), standard exclusions (R14), auto-detected
  # alternates (R12), and room inclusions (R8). All inserts run inside a single
  # transaction; an invalid record raises ActiveRecord::RecordInvalid and rolls
  # back every change.
  class BuildService
    # R11 — standard design clarifications pre-populated on creation.
    STANDARD_CLARIFICATIONS = [
      "All cabinet doors bid as slab and cabinet interiors bid as white melamine",
      "Drawers bid as slab fronts with 3/4\" white melamine drawers and soft close undermount drawer slides"
    ].freeze

    # R14 — standard exclusions pre-populated on creation, in order.
    STANDARD_EXCLUSIONS = [
      "Man doors",
      "Install of owner supplied furnishings",
      "Demolition",
      "Sinks",
      "In-wall blocking",
      "Holiday/after-hours/overtime work",
      "AWI Certification",
      "FSC certified material",
      "LEED certification",
      "Bonding",
      "Permits/fees",
      "Protection of completed work",
      "Traffic control for deliveries"
    ].freeze

    def initialize(estimate:)
      @estimate = estimate
    end

    # @return [Proposal] the persisted proposal with seeded children.
    def call
      ActiveRecord::Base.transaction do
        totals = EstimateTotalsCalculator.new(@estimate).call

        proposal = Proposal.new(
          estimate:     @estimate,
          job_name:     @estimate.title,
          total_amount: totals.burdened_total,
          mode:         :commercial,
          status:       :draft,
          current_step: "opening"
        )

        seed_clarifications(proposal)
        seed_exclusions(proposal)
        seed_alternates(proposal, totals)
        seed_inclusions(proposal)

        proposal.save!
        proposal
      end
    end

    private

    def seed_clarifications(proposal)
      STANDARD_CLARIFICATIONS.each do |body|
        proposal.proposal_clarifications.build(body: body)
      end
    end

    def seed_exclusions(proposal)
      STANDARD_EXCLUSIONS.each do |body|
        proposal.proposal_exclusions.build(body: body)
      end
    end

    def seed_alternates(proposal, totals)
      AlternateDetectorService.new(estimate: @estimate).call.each do |line_item|
        proposal.proposal_alternates.build(
          description:  line_item.description,
          line_item:    line_item,
          display_cost: alternate_display_cost(line_item, totals)
        )
      end
    end

    # Gross/burdened cost basis (OQ-E resolved): the line item's non-burdened
    # total multiplied by the estimate's burden multiplier, consistent with
    # total_amount using burdened_total. Job-level fixed costs are not
    # attributable to a single alternate line and are therefore excluded.
    #
    # Alternates come from estimate.line_items and line_item_results is keyed by
    # those same line items, so a missing entry is an internal inconsistency. We
    # fetch (raising KeyError) rather than defaulting to 0 — failing loud rolls
    # back the transaction instead of silently persisting a $0 alternate on a
    # client-facing bid.
    def alternate_display_cost(line_item, totals)
      result = totals.line_item_results.fetch(line_item.id)
      (result[:non_burdened_total] * totals.burden_multiplier).round(2)
    end

    def seed_inclusions(proposal)
      rooms = @estimate.line_items.pluck(:room).filter_map { |r| r&.strip.presence }.uniq
      rooms.each do |room|
        proposal.proposal_inclusions.build(room_name: room, bullet_points: nil)
      end
    end
  end
end
