class LineItem < ApplicationRecord
  belongs_to :estimate_section
  belongs_to :estimate_material, optional: true

  acts_as_list scope: :estimate_section

  LINE_ITEM_CATEGORIES = %w[material labor alternate buy_out other].freeze
  COMPONENT_TYPES = %w[exterior interior interior_2nd back banding drawers pulls hinges slides locks hardware other_material].freeze
  LABOR_CATEGORIES = %w[detail mill assembly customs finish install].freeze

  validates :description, presence: true
  validates :line_item_category, presence: true, inclusion: { in: LINE_ITEM_CATEGORIES }
  validates :markup_percent, numericality: { greater_than_or_equal_to: 0 }, allow_nil: true

  # Extended cost routing — three computation paths depending on category
  def extended_cost
    case line_item_category
    when "material" then material_extended_cost
    when "labor"    then labor_extended_cost
    else            freeform_extended_cost
    end
  end

  # Sell price = extended_cost × (1 + markup_percent / 100).
  # Meaningful for buy-out / alternate / other items where markup is set by the user.
  # For material / labor items markup_percent is typically 0, so sell_price == extended_cost.
  def sell_price
    pct = markup_percent || BigDecimal("0")
    extended_cost * (BigDecimal("1") + pct / BigDecimal("100"))
  end

  private

  def section_quantity
    estimate_section&.quantity || BigDecimal("1")
  end

  def material_extended_cost
    return BigDecimal("0") if estimate_material.nil? || component_quantity.nil?

    component_quantity * section_quantity * estimate_material.price_per_unit
  end

  # WARNING: Calls LaborRate.rate_for which issues a SQL query per invocation.
  # Do NOT call this from views that render many line items — use
  # EstimateTotalsCalculator instead, which preloads rates upfront.
  # This method is retained for unit-testing and single-item contexts only.
  def labor_extended_cost
    return BigDecimal("0") if hours_per_unit.nil? || labor_category.nil?

    rate = LaborRate.rate_for(labor_category)
    hours_per_unit * section_quantity * rate
  end

  def freeform_extended_cost
    qty = freeform_quantity || BigDecimal("0")
    cost = unit_cost || BigDecimal("0")
    qty * cost
  end
end
