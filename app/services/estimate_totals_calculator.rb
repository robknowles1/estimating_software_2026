class EstimateTotalsCalculator
  Result = Data.define(
    :line_item_results,        # Hash keyed by line_item.id
    :grand_non_burdened_total, # BigDecimal
    :burden_multiplier         # BigDecimal
  )

  LABOR_CATEGORIES = %w[detail mill assembly customs finish install].freeze

  def initialize(estimate)
    @estimate = estimate
  end

  def call
    estimate_materials_by_id = EstimateMaterial
      .where(estimate_id: @estimate.id)
      .index_by(&:id)

    locks_em    = estimate_materials_by_id.values.find { |em| em.role == "locks" }
    labor_rates = LaborRate.all.index_by(&:labor_category)

    burden_multiplier        = calculate_burden_multiplier
    line_item_results        = {}
    grand_non_burdened_total = BigDecimal("0")

    @estimate.line_items.each do |li|
      qty = li.quantity.to_d
      material_cost_per_unit = BigDecimal("0")

      %w[exterior interior interior2 back drawers pulls hinges slides].each do |slot|
        slot_qty = li.public_send(:"#{slot}_qty").to_d
        em       = estimate_materials_by_id[li.public_send(:"#{slot}_material_id")]
        material_cost_per_unit += slot_qty * em&.cost_with_tax.to_d
      end

      banding_em = estimate_materials_by_id[li.banding_material_id]
      material_cost_per_unit += banding_em&.cost_with_tax.to_d

      material_cost_per_unit += li.locks_qty.to_d * locks_em&.cost_with_tax.to_d

      material_cost_per_unit += li.other_material_cost.to_d

      subtotal_materials = material_cost_per_unit * qty

      labor_subtotals = {}
      LABOR_CATEGORIES.each do |cat|
        hrs  = li.public_send(:"#{cat}_hrs").to_d
        rate = labor_rates[cat]&.hourly_rate&.to_d || BigDecimal("0")
        labor_subtotals[cat] = hrs * rate * qty
      end

      equipment_total    = li.equipment_hrs.to_d * li.equipment_rate.to_d * qty
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
