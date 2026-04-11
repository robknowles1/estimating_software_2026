# Material represents one price-book slot for an estimate.
#
# Each estimate has a full set of slots seeded on creation (see Estimate#seed_materials).
# The estimator enters a quote_price for each slot; cost_with_tax is derived and stored
# for read performance (avoids a join to estimates at query time).
#
# cost_with_tax is recomputed:
#   - before_save on the Material itself (when quote_price is updated individually)
#   - via a single SQL UPDATE on all materials when estimate.tax_rate or tax_exempt changes
#     (see Estimate#recalculate_material_costs — avoids N+1 callbacks)
class Material < ApplicationRecord
  belongs_to :estimate

  # ── Slot definitions ────────────────────────────────────────────────────────
  #
  # Slot list verified against the Excel template (ADR-008 OQ-A resolved).
  # slot_key  — machine-readable identifier; stored in DB and used as FK target label
  # label     — optional human-readable override for display; falls back to slot_key
  # category  — "sheet_good" or "hardware"

  SLOTS = [
    # Sheet goods
    { slot_key: "PL1",               category: "sheet_good" },
    { slot_key: "PL2",               category: "sheet_good" },
    { slot_key: "PL3",               category: "sheet_good" },
    { slot_key: "PL4",               category: "sheet_good" },
    { slot_key: "PL5",               category: "sheet_good" },
    { slot_key: "PL6",               category: "sheet_good" },
    { slot_key: "QTR_MEL",           category: "sheet_good", label: '1/4" MEL' },
    { slot_key: "TH_MEL_G2S",        category: "sheet_good", label: '3/4" MEL G2S' },
    { slot_key: "TH_MEL_PLYCORE",    category: "sheet_good", label: '3/4" MEL PLYCORE' },
    { slot_key: "TH_MEL3",           category: "sheet_good", label: '3/4" MEL3' },
    { slot_key: "TH_MEL4",           category: "sheet_good", label: '3/4" MEL4' },
    { slot_key: "TH_MEL5",           category: "sheet_good", label: '3/4" MEL5' },
    { slot_key: "TH_MEL6",           category: "sheet_good", label: '3/4" MEL6' },
    { slot_key: "ONE_MEL1",          category: "sheet_good", label: '1" MEL1' },
    { slot_key: "ONE_MEL2",          category: "sheet_good", label: '1" MEL2' },
    { slot_key: "ONE_MEL3",          category: "sheet_good", label: '1" MEL3' },
    { slot_key: "VENEER1",           category: "sheet_good" },
    { slot_key: "VENEER2",           category: "sheet_good" },
    { slot_key: "VENEER3",           category: "sheet_good" },
    { slot_key: "VENEER4",           category: "sheet_good" },
    { slot_key: "VENEER5",           category: "sheet_good" },
    { slot_key: "VENEER6",           category: "sheet_good" },
    # Hardware
    { slot_key: "PULL1",             category: "hardware" },
    { slot_key: "PULL2",             category: "hardware" },
    { slot_key: "PULL3",             category: "hardware" },
    { slot_key: "PULL4",             category: "hardware" },
    { slot_key: "PULL5",             category: "hardware" },
    { slot_key: "PULL6",             category: "hardware" },
    { slot_key: "HINGE1",            category: "hardware" },
    { slot_key: "HINGE2",            category: "hardware" },
    { slot_key: "HINGE3",            category: "hardware" },
    { slot_key: "HINGE4",            category: "hardware" },
    { slot_key: "HINGE5",            category: "hardware" },
    { slot_key: "HINGE6",            category: "hardware" },
    { slot_key: "SLIDE1",            category: "hardware" },
    { slot_key: "SLIDE2",            category: "hardware" },
    { slot_key: "SLIDE3",            category: "hardware" },
    { slot_key: "SLIDE4",            category: "hardware" },
    { slot_key: "SLIDE5",            category: "hardware" },
    { slot_key: "SLIDE6",            category: "hardware" },
    { slot_key: "BANDING1",          category: "hardware" },
    { slot_key: "BANDING2",          category: "hardware" },
    { slot_key: "BANDING3",          category: "hardware" },
    { slot_key: "BANDING4",          category: "hardware" },
    { slot_key: "BANDING5",          category: "hardware" },
    { slot_key: "BANDING6",          category: "hardware" },
    { slot_key: "BALTIC_DOVETAIL",   category: "hardware" },
    { slot_key: "FH_MELAMINE",       category: "hardware", label: '5/8" MELAMINE' },
    { slot_key: "TH_MELAMINE",       category: "hardware", label: '3/4" MELAMINE' },
    { slot_key: "LOCKS",             category: "hardware" }
  ].freeze

  # ── Validations ──────────────────────────────────────────────────────────────

  validates :slot_key, presence: true, uniqueness: { scope: :estimate_id }
  validates :category, presence: true, inclusion: { in: %w[sheet_good hardware] }
  validates :quote_price, numericality: { greater_than_or_equal_to: 0 }, allow_nil: true

  # ── Callbacks ────────────────────────────────────────────────────────────────

  # Requires estimate to be preloaded (belongs_to ensures this via in-memory association).
  # Do NOT call save in a loop when changing tax_rate — use Estimate#recalculate_material_costs.
  before_save :compute_cost_with_tax

  # ── Display helpers ──────────────────────────────────────────────────────────

  # Returns the human-readable label for this slot, falling back to slot_key if no
  # label entry exists in SLOTS. Used in views instead of inline logic.
  def display_label
    slot_def = SLOTS.find { |s| s[:slot_key] == slot_key }
    slot_def&.dig(:label) || slot_key
  end

  private

  def compute_cost_with_tax
    rate = estimate&.tax_exempt? ? BigDecimal("0") : (estimate&.tax_rate || BigDecimal("0.08"))
    self.cost_with_tax = (quote_price || BigDecimal("0")) * (BigDecimal("1") + rate)
  end
end
