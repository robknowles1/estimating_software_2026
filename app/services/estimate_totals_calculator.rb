class EstimateTotalsCalculator
  Result = Data.define(
    :line_item_results,        # Hash keyed by line_item.id
    :grand_non_burdened_total, # BigDecimal
    :burden_multiplier,        # BigDecimal
    :job_level_costs,          # Hash of named fixed costs
    :burdened_total,           # BigDecimal
    :cogs_breakdown,           # Hash keyed by COGS category code string
    :labor_hours_summary,      # Hash of total hours per labor category
    :man_days_install          # BigDecimal
  )

  LABOR_CATEGORIES = %w[detail mill assembly customs finish install].freeze
  SHOP_LABOR_CATEGORIES = %w[detail mill assembly customs finish].freeze

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

    job_level_costs = calculate_job_level_costs
    job_level_costs_sum = job_level_costs.values.sum

    burdened_total = (grand_non_burdened_total * burden_multiplier) + job_level_costs_sum

    labor_hours_summary = calculate_labor_hours_summary(line_item_results)
    man_days_install = labor_hours_summary["install"] / BigDecimal("8")

    cogs_breakdown = calculate_cogs_breakdown(
      line_item_results,
      grand_non_burdened_total,
      job_level_costs
    )

    Result.new(
      line_item_results:        line_item_results,
      grand_non_burdened_total: grand_non_burdened_total,
      burden_multiplier:        burden_multiplier,
      job_level_costs:          job_level_costs,
      burdened_total:           burdened_total,
      cogs_breakdown:           cogs_breakdown,
      labor_hours_summary:      labor_hours_summary,
      man_days_install:         man_days_install
    )
  end

  private

  def calculate_burden_multiplier
    profit_pct = @estimate.profit_overhead_percent.to_d
    pm_pct     = @estimate.pm_supervision_percent.to_d
    (BigDecimal("1") + profit_pct / BigDecimal("100")) *
      (BigDecimal("1") + pm_pct   / BigDecimal("100"))
  end

  def calculate_job_level_costs
    constants         = Rails.application.config.burden_constants
    mileage_rate      = constants[:mileage_rate]
    hotel_rate        = constants[:hotel_rate]
    airfare_rate      = constants[:airfare_rate]
    crew              = @estimate.installer_crew_size.to_d

    install_travel_cost = @estimate.install_travel_qty.to_d * crew * mileage_rate * BigDecimal("2")
    delivery_cost       = @estimate.delivery_qty.to_d * @estimate.delivery_rate.to_d
    per_diem_cost       = @estimate.per_diem_qty.to_d * @estimate.per_diem_rate.to_d * crew
    hotel_cost          = @estimate.hotel_qty.to_d * crew * hotel_rate
    airfare_cost        = @estimate.airfare_qty.to_d * crew * airfare_rate

    {
      install_travel: install_travel_cost,
      delivery:       delivery_cost,
      per_diem:       per_diem_cost,
      hotel:          hotel_cost,
      airfare:        airfare_cost
    }
  end

  def calculate_labor_hours_summary(line_item_results)
    summary = LABOR_CATEGORIES.index_with { BigDecimal("0") }

    @estimate.line_items.each do |li|
      result = line_item_results[li.id]
      next unless result

      qty = li.quantity.to_d
      LABOR_CATEGORIES.each do |cat|
        summary[cat] += li.public_send(:"#{cat}_hrs").to_d * qty
      end
    end

    summary
  end

  def calculate_cogs_breakdown(line_item_results, grand_non_burdened_total, job_level_costs)
    # 100 Materials: sum of all line item subtotal_materials
    materials_total = line_item_results.values.sum { |r| r[:subtotal_materials] }

    # 200 Engineering: grand_non_burdened_total * (pm_supervision_percent / 100)
    pm_pct      = @estimate.pm_supervision_percent.to_d
    engineering = grand_non_burdened_total * (pm_pct / BigDecimal("100"))

    # 300 Shop Labor: sum of detail, mill, assembly, customs, finish labor subtotals
    shop_labor = line_item_results.values.sum do |r|
      SHOP_LABOR_CATEGORIES.sum { |cat| r[:labor_subtotals][cat] || BigDecimal("0") }
    end

    # 400 Install: install labor subtotals + install_travel + per_diem + hotel + airfare
    install_labor = line_item_results.values.sum { |r| r[:labor_subtotals]["install"] || BigDecimal("0") }
    install_total = install_labor +
                    job_level_costs[:install_travel] +
                    job_level_costs[:per_diem] +
                    job_level_costs[:hotel] +
                    job_level_costs[:airfare]

    # 600 Countertops: countertop_quote
    countertop = @estimate.countertop_quote.to_d

    {
      "100_materials"   => materials_total,
      "200_engineering" => engineering,
      "300_shop_labor"  => shop_labor,
      "400_install"     => install_total,
      "500_sub_install" => BigDecimal("0"),
      "600_countertops" => countertop,
      "700_sub_other"   => BigDecimal("0")
    }
  end
end
