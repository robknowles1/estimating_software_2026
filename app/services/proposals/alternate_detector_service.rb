module Proposals
  # Detects line items on an estimate that represent alternates.
  #
  # A line item is an alternate when its +description+ begins with a recognised
  # alternate prefix (ALT / Alt. / Alternate, case-insensitive). Detection uses
  # +Proposal::ALTERNATE_PREFIXES+ as the single source of truth and filters in
  # Ruby (the estimate's line item count is small enough that a single query plus
  # an in-memory filter is fast and avoids ILIKE prefix edge cases).
  class AlternateDetectorService
    def initialize(estimate:)
      @estimate = estimate
    end

    # @return [Array<LineItem>] matching line items in stable position order,
    #   or [] when none match.
    def call
      # Estimate declares `has_many :line_items, -> { order(:position) }`, so the
      # relation is already position-ordered; we add :id only as a stable tie-break.
      @estimate.line_items
        .order(:position, :id)
        .select { |li| li.description.to_s.match?(Proposal::ALTERNATE_PREFIXES) }
    end
  end
end
