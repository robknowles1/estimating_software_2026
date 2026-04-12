class EstimateTotalsCalculator
  Result = Data.define(
    :line_item_results,        # Hash keyed by line_item.id => { material_cost_per_unit:, subtotal_materials:, labor_subtotals:, equipment_total:, non_burdened_total: }
    :grand_non_burdened_total, # BigDecimal
    :burden_multiplier         # BigDecimal
  )

  MATERIAL_SLOTS = [
    [ :exterior,   :exterior_material_id   ],
    [ :interior,   :interior_material_id   ],
    [ :interior2,  :interior2_material_id  ],
    [ :back,       :back_material_id       ],
    [ :banding,    nil                     ], # no qty column — zero cost in this phase (OQ-B)
    [ :drawers,    :drawers_material_id    ],
    [ :pulls,      :pulls_material_id      ],
    [ :hinges,     :hinges_material_id     ],
    [ :slides,     :slides_material_id     ]
  ].freeze

  LABOR_CATEGORIES = %w[detail mill assembly customs finish install].freeze

  def initialize(estimate)
    @estimate = estimate
  end

  def call
    # Load materials indexed two ways — never query inside the loop
    materials_by_id       = @estimate.materials.index_by(&:id)
    materials_by_slot_key = @estimate.materials.index_by(&:slot_key)

    # Load all labor rates indexed by category — never query inside the loop
    labor_rates = LaborRate.all.index_by(&:labor_category)

    burden_multiplier = calculate_burden_multiplier

    line_item_results = {}
    grand_non_burdened_total = BigDecimal("0")

    @estimate.line_items.each do |li|
      qty = li.quantity.to_d

      # ── Material cost per unit ─────────────────────────────────────────────────
      material_cost_per_unit = BigDecimal("0")

      MATERIAL_SLOTS.each do |slot_name, fk_column|
        next if fk_column.nil? # banding: no qty, zero cost

        material_id = li.public_send(fk_column)
        next if material_id.nil?

        qty_col     = :"#{slot_name}_qty"
        slot_qty    = li.public_send(qty_col).to_d
        mat_cost    = materials_by_id[material_id]&.cost_with_tax.to_d

        material_cost_per_unit += slot_qty * mat_cost
      end

      # Locks: qty-only slot, price from LOCKS slot_key
      locks_qty  = li.locks_qty.to_d
      locks_cost = materials_by_slot_key["LOCKS"]&.cost_with_tax.to_d || BigDecimal("0")
      material_cost_per_unit += locks_qty * locks_cost

      # Other freeform material cost
      material_cost_per_unit += li.other_material_cost.to_d

      subtotal_materials = material_cost_per_unit * qty

      # ── Labor subtotals ────────────────────────────────────────────────────────
      labor_subtotals = {}
      LABOR_CATEGORIES.each do |cat|
        hrs  = li.public_send(:"#{cat}_hrs").to_d
        rate = labor_rates[cat]&.hourly_rate.to_d || BigDecimal("0")
        labor_subtotals[cat] = hrs * rate * qty
      end

      # ── Equipment ─────────────────────────────────────────────────────────────
      equipment_total = li.equipment_hrs.to_d * li.equipment_rate.to_d * qty

      # ── Non-burdened total ────────────────────────────────────────────────────
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
