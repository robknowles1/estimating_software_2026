class EstimateTotalsCalculator
  Result = Data.define(
    :line_item_results,        # Hash keyed by line_item.id
    :grand_non_burdened_total, # BigDecimal
    :burden_multiplier         # BigDecimal
  )

  # Slots with qty multiplier (qty * unit_price)
  TYPED_SLOTS = %w[exterior interior interior2 back drawers pulls hinges slides locks].freeze
  LABOR_CATEGORIES = %w[detail mill assembly customs finish install].freeze

  def initialize(estimate)
    @estimate = estimate
  end

  def call
    # One query — labor rates indexed by category
    labor_rates = LaborRate.all.index_by(&:labor_category)

    burden_multiplier        = calculate_burden_multiplier
    line_item_results        = {}
    grand_non_burdened_total = BigDecimal("0")

    @estimate.line_items.each do |li|
      qty = li.quantity.to_d

      # Material cost per unit
      material_cost_per_unit = BigDecimal("0")

      TYPED_SLOTS.each do |slot|
        slot_qty   = li.public_send(:"#{slot}_qty").to_d
        slot_price = li.public_send(:"#{slot}_unit_price").to_d
        material_cost_per_unit += slot_qty * slot_price
      end

      # Banding — flat per-unit, no qty multiplier
      material_cost_per_unit += li.banding_unit_price.to_d

      # Other freeform cost per unit
      material_cost_per_unit += li.other_material_cost.to_d

      subtotal_materials = material_cost_per_unit * qty

      # Labor subtotals
      labor_subtotals = {}
      LABOR_CATEGORIES.each do |cat|
        hrs  = li.public_send(:"#{cat}_hrs").to_d
        rate = labor_rates[cat]&.hourly_rate&.to_d || BigDecimal("0")
        labor_subtotals[cat] = hrs * rate * qty
      end

      # Equipment
      equipment_total = li.equipment_hrs.to_d * li.equipment_rate.to_d * qty

      non_burdened_total = subtotal_materials + labor_subtotals.values.sum + equipment_total

      line_item_results[li.id] = {
        material_cost_per_unit: material_cost_per_unit,
        subtotal_materials:     subtotal_materials,
        labor_subtotals:        labor_subtotals,
        equipment_total:        equipment_total,
        non_burdened_total:     non_burdened_total
      }

      grand_non_burdened_total += non_burdened_total
    end

    Result.new(
      line_item_results:        line_item_results,
      grand_non_burdened_total: grand_non_burdened_total,
      burden_multiplier:        burden_multiplier
    )
  end

  private

  def calculate_burden_multiplier
    profit_pct = @estimate.profit_overhead_percent.to_d
    pm_pct     = @estimate.pm_supervision_percent.to_d
    (BigDecimal("1") + profit_pct / BigDecimal("100")) *
      (BigDecimal("1") + pm_pct   / BigDecimal("100"))
  end
end
