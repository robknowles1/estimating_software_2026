class EstimateTotalsCalculator
  Result = Data.define(
    :section_subtotals,        # { section_id => { non_burdened: X, burdened: Y } }
    :alternate_total,          # { non_burdened: X, sell: Y }
    :buy_out_total,            # { cost: X, sell: Y }
    :grand_total_non_burdened, # sum across all material+labor sections
    :grand_total_burdened      # grand_total_non_burdened with burden factors applied
  )

  def initialize(estimate)
    @estimate = estimate
  end

  def call
    # Cache labor rates upfront to avoid per-line-item queries inside the loop
    @labor_rates = LaborRate.all.index_by(&:labor_category)

    section_subtotals = {}
    grand_total_non_burdened = BigDecimal("0")
    alternate_non_burdened = BigDecimal("0")
    alternate_sell = BigDecimal("0")
    buy_out_cost = BigDecimal("0")
    buy_out_sell = BigDecimal("0")

    # Pass 1: compute non_burdened per section and accumulate grand total
    @estimate.estimate_sections.each do |section|
      non_burdened = BigDecimal("0")

      section.line_items.each do |item|
        case item.line_item_category
        when "material", "labor"
          non_burdened += extended_cost_for(item, section)
        when "other"
          non_burdened += freeform_cost_for(item)
        when "alternate"
          ec = freeform_cost_for(item)
          alternate_non_burdened += ec
          pct = item.markup_percent || BigDecimal("0")
          alternate_sell += ec * (BigDecimal("1") + pct / BigDecimal("100"))
        when "buy_out"
          ec = freeform_cost_for(item)
          buy_out_cost += ec
          pct = item.markup_percent || BigDecimal("0")
          buy_out_sell += ec * (BigDecimal("1") + pct / BigDecimal("100"))
        end
      end

      section_subtotals[section.id] = { non_burdened: non_burdened, burdened: BigDecimal("0") }
      grand_total_non_burdened += non_burdened
    end

    # Pass 2: compute burdened per section using travel cost proration
    total_travel_cost = calculate_total_travel_cost
    burden_multiplier = calculate_burden_multiplier

    @estimate.estimate_sections.each do |section|
      nb = section_subtotals[section.id][:non_burdened]

      travel_share = if grand_total_non_burdened > 0
        total_travel_cost * (nb / grand_total_non_burdened)
      else
        BigDecimal("0")
      end

      burdened = (nb * burden_multiplier) + travel_share
      section_subtotals[section.id][:burdened] = burdened
    end

    # Only add travel cost when there is non-burdened work to prorate it against.
    # When grand_total_non_burdened is 0, per-section travel_share is also 0 (see above),
    # so the grand total must match — adding travel here would create an inconsistency.
    grand_total_travel = grand_total_non_burdened > 0 ? total_travel_cost : BigDecimal("0")
    grand_total_burdened = (grand_total_non_burdened * burden_multiplier) + grand_total_travel

    Result.new(
      section_subtotals: section_subtotals,
      alternate_total: { non_burdened: alternate_non_burdened, sell: alternate_sell },
      buy_out_total: { cost: buy_out_cost, sell: buy_out_sell },
      grand_total_non_burdened: grand_total_non_burdened,
      grand_total_burdened: grand_total_burdened
    )
  end

  private

  def extended_cost_for(item, section)
    case item.line_item_category
    when "material"
      return BigDecimal("0") if item.estimate_material.nil? || item.component_quantity.nil?

      item.component_quantity * section.quantity * item.estimate_material.price_per_unit
    when "labor"
      return BigDecimal("0") if item.hours_per_unit.nil? || item.labor_category.nil?

      rate = labor_rate_for(item.labor_category)
      item.hours_per_unit * section.quantity * rate
    else
      BigDecimal("0")
    end
  end

  def freeform_cost_for(item)
    qty = item.freeform_quantity || BigDecimal("0")
    cost = item.unit_cost || BigDecimal("0")
    qty * cost
  end

  def labor_rate_for(category)
    @labor_rates[category]&.hourly_rate || BigDecimal("0")
  end

  def calculate_total_travel_cost
    miles = @estimate.miles_to_jobsite || BigDecimal("0")
    return BigDecimal("0") if miles <= 0

    constants = Rails.application.config.burden_constants
    mileage_rate = constants[:mileage_rate]
    round_trip = BigDecimal(constants[:round_trip_factor].to_s)

    installer_crew = BigDecimal(@estimate.installer_crew_size.to_s)
    delivery_crew = BigDecimal(@estimate.delivery_crew_size.to_s)

    install_travel = miles * round_trip * installer_crew * mileage_rate
    delivery_travel = miles * round_trip * delivery_crew * mileage_rate
    install_travel + delivery_travel
  end

  def calculate_burden_multiplier
    profit_pct = @estimate.profit_overhead_percent || BigDecimal("0")
    pm_pct = @estimate.pm_supervision_percent || BigDecimal("0")

    (BigDecimal("1") + profit_pct / BigDecimal("100")) *
      (BigDecimal("1") + pm_pct / BigDecimal("100"))
  end
end
