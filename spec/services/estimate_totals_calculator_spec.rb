require "rails_helper"

RSpec.describe EstimateTotalsCalculator do
  let(:estimate) do
    create(:estimate,
           profit_overhead_percent: BigDecimal("0"),
           pm_supervision_percent:  BigDecimal("0"),
           tax_rate:                BigDecimal("0"),
           tax_exempt:              false,
           installer_crew_size:     2,
           install_travel_qty:      BigDecimal("0"),
           delivery_qty:            BigDecimal("0"),
           delivery_rate:           BigDecimal("400.00"),
           per_diem_qty:            BigDecimal("0"),
           per_diem_rate:           BigDecimal("65.00"),
           hotel_qty:               BigDecimal("0"),
           airfare_qty:             BigDecimal("0"),
           countertop_quote:        BigDecimal("0"))
  end

  let!(:detail_rate)   { create(:labor_rate, labor_category: "detail",   hourly_rate: BigDecimal("20.00")) }
  let!(:mill_rate)     { create(:labor_rate, labor_category: "mill",     hourly_rate: BigDecimal("22.00")) }
  let!(:assembly_rate) { create(:labor_rate, labor_category: "assembly", hourly_rate: BigDecimal("25.00")) }
  let!(:customs_rate)  { create(:labor_rate, labor_category: "customs",  hourly_rate: BigDecimal("18.00")) }
  let!(:finish_rate)   { create(:labor_rate, labor_category: "finish",   hourly_rate: BigDecimal("21.00")) }
  let!(:install_rate)  { create(:labor_rate, labor_category: "install",  hourly_rate: BigDecimal("23.00")) }

  def preloaded_estimate
    Estimate.includes(:line_items).find(estimate.id)
  end

  subject(:calculator) { described_class.new(preloaded_estimate) }

  describe "#call with no line items" do
    it "returns grand_non_burdened_total of zero" do
      result = calculator.call
      expect(result.grand_non_burdened_total).to eq(BigDecimal("0"))
    end

    it "returns an empty line_item_results hash" do
      result = calculator.call
      expect(result.line_item_results).to be_empty
    end

    it "returns burdened_total of zero when no line items and no job costs" do
      result = calculator.call
      expect(result.burdened_total).to eq(BigDecimal("0"))
    end
  end

  describe "#call material cost computation" do
    context "with exterior_material_id and exterior_qty set" do
      let!(:material) { create(:material, default_price: BigDecimal("50.00")) }
      let!(:em)       { create(:estimate_material, estimate: estimate, material: material, quote_price: BigDecimal("50.00")) }
      let!(:li) do
        create(:line_item, estimate: estimate,
               exterior_material_id: em.id,
               exterior_qty: BigDecimal("2.0"),
               quantity: BigDecimal("1"))
      end

      it "computes material_cost_per_unit as exterior_qty * em.cost_with_tax" do
        result = calculator.call
        expect(result.line_item_results[li.id][:material_cost_per_unit]).to eq(BigDecimal("100.00"))
      end
    end

    context "with null exterior_material_id" do
      let!(:li) do
        create(:line_item, estimate: estimate,
               exterior_material_id: nil,
               exterior_qty: BigDecimal("2.0"),
               quantity: BigDecimal("1"))
      end

      it "contributes zero without raising" do
        expect { calculator.call }.not_to raise_error
        result = calculator.call
        expect(result.line_item_results[li.id][:material_cost_per_unit]).to eq(BigDecimal("0"))
      end
    end

    context "with banding_material_id set (no qty multiplier)" do
      let!(:material) { create(:material, default_price: BigDecimal("8.50")) }
      let!(:em)       { create(:estimate_material, estimate: estimate, material: material, quote_price: BigDecimal("8.50")) }
      let!(:li) do
        create(:line_item, estimate: estimate,
               banding_material_id: em.id,
               quantity: BigDecimal("1"))
      end

      it "applies cost_with_tax directly without qty multiplier" do
        result = calculator.call
        expect(result.line_item_results[li.id][:material_cost_per_unit]).to eq(BigDecimal("8.50"))
      end
    end

    context "with banding_material_id nil" do
      let!(:li) do
        create(:line_item, estimate: estimate,
               banding_material_id: nil,
               quantity: BigDecimal("1"))
      end

      it "contributes zero without raising" do
        result = calculator.call
        expect(result.line_item_results[li.id][:material_cost_per_unit]).to eq(BigDecimal("0"))
      end
    end

    context "with locks_qty and a locks-role estimate_material" do
      let!(:material) { create(:material, default_price: BigDecimal("12.00")) }
      let!(:em)       { create(:estimate_material, estimate: estimate, material: material, quote_price: BigDecimal("12.00"), role: "locks") }
      let!(:li) do
        create(:line_item, estimate: estimate,
               locks_qty: BigDecimal("3.0"),
               quantity: BigDecimal("1"))
      end

      it "includes locks_qty * locks_em.cost_with_tax in material cost" do
        result = calculator.call
        expect(result.line_item_results[li.id][:material_cost_per_unit]).to eq(BigDecimal("36.00"))
      end
    end

    context "when no locks-role estimate_material exists" do
      let!(:li) do
        create(:line_item, estimate: estimate,
               locks_qty: BigDecimal("2.0"),
               quantity: BigDecimal("1"))
      end

      it "contributes zero for locks without raising" do
        result = calculator.call
        expect(result.line_item_results[li.id][:material_cost_per_unit]).to eq(BigDecimal("0"))
      end
    end

    context "with other_material_cost set" do
      let!(:li) do
        create(:line_item, estimate: estimate,
               other_material_cost: BigDecimal("15.00"),
               quantity: BigDecimal("1"))
      end

      it "includes other_material_cost in material cost" do
        result = calculator.call
        expect(result.line_item_results[li.id][:material_cost_per_unit]).to eq(BigDecimal("15.00"))
      end
    end

    context "with all nil slot values" do
      let!(:li) { create(:line_item, estimate: estimate, quantity: BigDecimal("1")) }

      it "returns zero material cost without nil arithmetic errors" do
        expect { calculator.call }.not_to raise_error
        result = calculator.call
        expect(result.line_item_results[li.id][:material_cost_per_unit]).to eq(BigDecimal("0"))
      end
    end

    context "with multiple slots and quantity > 1" do
      let!(:material) { create(:material, default_price: BigDecimal("50.00")) }
      let!(:em_ext)   { create(:estimate_material, estimate: estimate, material: material, quote_price: BigDecimal("50.00")) }
      let!(:mat2)     { create(:material, default_price: BigDecimal("5.00")) }
      let!(:em_band)  { create(:estimate_material, estimate: estimate, material: mat2, quote_price: BigDecimal("5.00")) }
      let!(:li) do
        create(:line_item, estimate: estimate,
               exterior_material_id: em_ext.id,
               exterior_qty: BigDecimal("2.0"),
               banding_material_id: em_band.id,
               quantity: BigDecimal("3"))
      end

      it "multiplies subtotal_materials by quantity" do
        result = calculator.call
        # material_cost_per_unit = (2.0 * 50.00) + 5.00 = 105.00
        # subtotal_materials = 105.00 * 3 = 315.00
        expect(result.line_item_results[li.id][:subtotal_materials]).to eq(BigDecimal("315.00"))
      end
    end
  end

  describe "#call labor computation" do
    let!(:li) do
      create(:line_item, estimate: estimate,
             detail_hrs: BigDecimal("1.0"), assembly_hrs: BigDecimal("0.5"),
             quantity: BigDecimal("2"))
    end

    it "computes labor subtotals per category" do
      result = calculator.call
      subtotals = result.line_item_results[li.id][:labor_subtotals]
      expect(subtotals["detail"]).to eq(BigDecimal("40.00"))
      expect(subtotals["assembly"]).to eq(BigDecimal("25.00"))
    end
  end

  describe "#call burden multiplier" do
    context "with no burden factors" do
      it "returns burden_multiplier of 1" do
        result = calculator.call
        expect(result.burden_multiplier).to eq(BigDecimal("1"))
      end
    end

    context "with profit_overhead_percent = 20 and pm_supervision_percent = 10" do
      before { estimate.update!(profit_overhead_percent: 20, pm_supervision_percent: 10) }

      it "returns burden_multiplier as 1.20 * 1.10 = 1.32" do
        result = described_class.new(preloaded_estimate).call
        expect(result.burden_multiplier).to eq(BigDecimal("1.32"))
      end
    end
  end

  describe "#call grand_non_burdened_total" do
    let!(:material1) { create(:material, default_price: BigDecimal("100.00")) }
    let!(:material2) { create(:material, default_price: BigDecimal("50.00")) }
    let!(:em1)       { create(:estimate_material, estimate: estimate, material: material1, quote_price: BigDecimal("100.00")) }
    let!(:em2)       { create(:estimate_material, estimate: estimate, material: material2, quote_price: BigDecimal("50.00")) }

    let!(:li1) do
      create(:line_item, estimate: estimate,
             exterior_material_id: em1.id,
             exterior_qty: BigDecimal("1.0"),
             quantity: BigDecimal("1"))
    end
    let!(:li2) do
      create(:line_item, estimate: estimate,
             exterior_material_id: em2.id,
             exterior_qty: BigDecimal("2.0"),
             quantity: BigDecimal("1"))
    end

    it "sums non_burdened_total across all line items" do
      result = described_class.new(preloaded_estimate).call
      # li1: 1.0 * 100 = 100; li2: 2.0 * 50 = 100; total = 200
      expect(result.grand_non_burdened_total).to eq(BigDecimal("200.00"))
    end
  end

  describe "#call uses BigDecimal arithmetic" do
    let!(:material) { create(:material, default_price: BigDecimal("3.0")) }
    let!(:em)       { create(:estimate_material, estimate: estimate, material: material, quote_price: BigDecimal("3.0")) }
    let!(:li) do
      create(:line_item, estimate: estimate,
             exterior_material_id: em.id,
             exterior_qty: BigDecimal("1.3333"),
             quantity: BigDecimal("1"))
    end

    it "returns BigDecimal result without floating point rounding errors" do
      result = calculator.call
      mat = result.line_item_results[li.id][:material_cost_per_unit]
      expect(mat).to be_a(BigDecimal)
      expect(mat).to eq(BigDecimal("1.3333") * BigDecimal("3.0"))
    end
  end

  describe "#call query count" do
    let!(:li1) { create(:line_item, estimate: estimate, quantity: BigDecimal("1")) }
    let!(:li2) { create(:line_item, estimate: estimate, quantity: BigDecimal("1")) }

    it "fires at most 2 database queries (estimate_materials + labor_rates) regardless of line item count" do
      loaded = preloaded_estimate

      query_count = 0
      counter = lambda do |_name, _start, _finish, _id, payload|
        next if %w[SCHEMA TRANSACTION CACHE].include?(payload[:name])
        query_count += 1
      end

      ActiveSupport::Notifications.subscribed(counter, "sql.active_record") do
        described_class.new(loaded).call
      end

      expect(query_count).to be <= 2
    end
  end

  # -----------------------------------------------------------------------
  # SPEC-012: Job-level cost tests
  # -----------------------------------------------------------------------

  describe "#call job-level fixed costs" do
    describe "install_travel_cost" do
      it "computes install_travel_cost = install_travel_qty * installer_crew_size * mileage_rate * 2" do
        # 3 trips * 2 crew * $0.67/mile * 2 (round trip) = $8.04
        estimate.update!(install_travel_qty: BigDecimal("3"), installer_crew_size: 2)
        result = described_class.new(preloaded_estimate).call
        mileage_rate = Rails.application.config.burden_constants[:mileage_rate]
        expected = BigDecimal("3") * BigDecimal("2") * mileage_rate * BigDecimal("2")
        expect(result.job_level_costs[:install_travel]).to eq(expected)
      end

      it "is zero when install_travel_qty is zero" do
        result = calculator.call
        expect(result.job_level_costs[:install_travel]).to eq(BigDecimal("0"))
      end
    end

    describe "delivery_cost" do
      it "computes delivery_cost = delivery_qty * delivery_rate" do
        estimate.update!(delivery_qty: BigDecimal("4"), delivery_rate: BigDecimal("500.00"))
        result = described_class.new(preloaded_estimate).call
        expect(result.job_level_costs[:delivery]).to eq(BigDecimal("2000.00"))
      end

      it "is zero when delivery_qty is zero" do
        result = calculator.call
        expect(result.job_level_costs[:delivery]).to eq(BigDecimal("0"))
      end
    end

    describe "per_diem_cost" do
      it "computes per_diem_cost = per_diem_qty * per_diem_rate * installer_crew_size" do
        estimate.update!(per_diem_qty: BigDecimal("5"), per_diem_rate: BigDecimal("65.00"), installer_crew_size: 2)
        result = described_class.new(preloaded_estimate).call
        # 5 * 65.00 * 2 = 650.00
        expect(result.job_level_costs[:per_diem]).to eq(BigDecimal("650.00"))
      end
    end

    describe "hotel_cost" do
      it "computes hotel_cost = hotel_qty * installer_crew_size * hotel_rate" do
        hotel_rate = Rails.application.config.burden_constants[:hotel_rate]
        estimate.update!(hotel_qty: BigDecimal("3"), installer_crew_size: 2)
        result = described_class.new(preloaded_estimate).call
        # 3 * 2 * 150.00 = 900.00
        expected = BigDecimal("3") * BigDecimal("2") * hotel_rate
        expect(result.job_level_costs[:hotel]).to eq(expected)
      end
    end

    describe "airfare_cost" do
      it "computes airfare_cost = airfare_qty * installer_crew_size * airfare_rate" do
        airfare_rate = Rails.application.config.burden_constants[:airfare_rate]
        estimate.update!(airfare_qty: BigDecimal("2"), installer_crew_size: 3)
        result = described_class.new(preloaded_estimate).call
        # 2 * 3 * 400.00 = 2400.00
        expected = BigDecimal("2") * BigDecimal("3") * airfare_rate
        expect(result.job_level_costs[:airfare]).to eq(expected)
      end
    end
  end

  describe "#call burdened_total" do
    it "equals grand_non_burdened_total * burden_multiplier + sum(job_level_fixed_costs)" do
      estimate.update!(
        profit_overhead_percent: BigDecimal("10"),
        pm_supervision_percent:  BigDecimal("4"),
        installer_crew_size:     2,
        install_travel_qty:      BigDecimal("1"),
        delivery_qty:            BigDecimal("2"),
        delivery_rate:           BigDecimal("400.00"),
        per_diem_qty:            BigDecimal("3"),
        per_diem_rate:           BigDecimal("65.00"),
        hotel_qty:               BigDecimal("2"),
        airfare_qty:             BigDecimal("0"),
        countertop_quote:        BigDecimal("500.00")
      )

      # Add a line item with known cost
      material = create(:material, default_price: BigDecimal("100.00"))
      em       = create(:estimate_material, estimate: estimate, material: material, quote_price: BigDecimal("100.00"))
      create(:line_item, estimate: estimate,
             exterior_material_id: em.id,
             exterior_qty: BigDecimal("1.0"),
             quantity: BigDecimal("1"))

      result = described_class.new(preloaded_estimate).call

      burden_multiplier = result.burden_multiplier
      job_costs_sum     = result.job_level_costs.values.sum

      expected = (result.grand_non_burdened_total * burden_multiplier) + job_costs_sum
      expect(result.burdened_total).to eq(expected)
    end

    it "uses BigDecimal arithmetic throughout" do
      result = calculator.call
      expect(result.burdened_total).to be_a(BigDecimal)
    end
  end

  describe "#call COGS breakdown" do
    let!(:material)  { create(:material, default_price: BigDecimal("200.00")) }
    let!(:em)        { create(:estimate_material, estimate: estimate, material: material, quote_price: BigDecimal("200.00")) }

    let!(:li) do
      create(:line_item, estimate: estimate,
             exterior_material_id: em.id,
             exterior_qty:   BigDecimal("1.0"),
             detail_hrs:     BigDecimal("2.0"),
             mill_hrs:       BigDecimal("1.0"),
             assembly_hrs:   BigDecimal("0.5"),
             customs_hrs:    BigDecimal("0.5"),
             finish_hrs:     BigDecimal("1.0"),
             install_hrs:    BigDecimal("3.0"),
             quantity:       BigDecimal("1"))
    end

    subject(:result) { described_class.new(preloaded_estimate).call }

    describe "100 Materials" do
      it "equals sum of all line item subtotal_materials" do
        # 1.0 * 200.00 = 200.00
        expect(result.cogs_breakdown["100_materials"]).to eq(BigDecimal("200.00"))
      end
    end

    describe "200 Engineering" do
      it "equals grand_non_burdened_total * (pm_supervision_percent / 100)" do
        estimate.update!(pm_supervision_percent: BigDecimal("4"))
        result = described_class.new(preloaded_estimate).call
        expected = result.grand_non_burdened_total * (BigDecimal("4") / BigDecimal("100"))
        expect(result.cogs_breakdown["200_engineering"]).to eq(expected)
      end

      it "is zero when pm_supervision_percent is zero" do
        expect(result.cogs_breakdown["200_engineering"]).to eq(BigDecimal("0"))
      end
    end

    describe "300 Shop Labor" do
      it "includes detail, mill, assembly, customs, and finish labor — NOT install" do
        expected_shop = (BigDecimal("2.0") * BigDecimal("20.00")) +  # detail
                        (BigDecimal("1.0") * BigDecimal("22.00")) +  # mill
                        (BigDecimal("0.5") * BigDecimal("25.00")) +  # assembly
                        (BigDecimal("0.5") * BigDecimal("18.00")) +  # customs
                        (BigDecimal("1.0") * BigDecimal("21.00"))    # finish
        expect(result.cogs_breakdown["300_shop_labor"]).to eq(expected_shop)
      end

      it "does not include install labor" do
        install_subtotal = BigDecimal("3.0") * BigDecimal("23.00")
        # 300_shop_labor must equal the shop-only total (without install)
        expected_shop = (BigDecimal("2.0") * BigDecimal("20.00")) +
                        (BigDecimal("1.0") * BigDecimal("22.00")) +
                        (BigDecimal("0.5") * BigDecimal("25.00")) +
                        (BigDecimal("0.5") * BigDecimal("18.00")) +
                        (BigDecimal("1.0") * BigDecimal("21.00"))
        # If install were included, shop_labor would be expected_shop + install_subtotal
        expect(result.cogs_breakdown["300_shop_labor"]).not_to eq(expected_shop + install_subtotal)
        # And it must be strictly less than grand_non_burdened_total (which includes install)
        expect(result.cogs_breakdown["300_shop_labor"]).to be < result.grand_non_burdened_total
      end
    end

    describe "400 Install" do
      it "includes install labor subtotals" do
        install_labor = BigDecimal("3.0") * BigDecimal("23.00") # = 69.00
        expect(result.cogs_breakdown["400_install"]).to be >= install_labor
      end

      it "includes install_travel, per_diem, hotel, and airfare costs" do
        estimate.update!(
          install_travel_qty: BigDecimal("1"),
          installer_crew_size: 2,
          per_diem_qty: BigDecimal("2"),
          per_diem_rate: BigDecimal("65.00"),
          hotel_qty: BigDecimal("1"),
          airfare_qty: BigDecimal("1")
        )
        result = described_class.new(preloaded_estimate).call

        mileage_rate = Rails.application.config.burden_constants[:mileage_rate]
        hotel_rate   = Rails.application.config.burden_constants[:hotel_rate]
        airfare_rate = Rails.application.config.burden_constants[:airfare_rate]

        install_travel = BigDecimal("1") * BigDecimal("2") * mileage_rate * BigDecimal("2")
        per_diem       = BigDecimal("2") * BigDecimal("65.00") * BigDecimal("2")
        hotel          = BigDecimal("1") * BigDecimal("2") * hotel_rate
        airfare        = BigDecimal("1") * BigDecimal("2") * airfare_rate
        install_labor  = BigDecimal("3.0") * BigDecimal("23.00")

        expected = install_labor + install_travel + per_diem + hotel + airfare
        expect(result.cogs_breakdown["400_install"]).to eq(expected)
      end
    end

    describe "500 Sub Install" do
      it "is zero (reserved)" do
        expect(result.cogs_breakdown["500_sub_install"]).to eq(BigDecimal("0"))
      end
    end

    describe "600 Countertops" do
      it "equals countertop_quote" do
        estimate.update!(countertop_quote: BigDecimal("1250.00"))
        result = described_class.new(preloaded_estimate).call
        expect(result.cogs_breakdown["600_countertops"]).to eq(BigDecimal("1250.00"))
      end

      it "is zero when countertop_quote is zero" do
        expect(result.cogs_breakdown["600_countertops"]).to eq(BigDecimal("0"))
      end
    end

    describe "700 Sub Other" do
      it "is zero (reserved)" do
        expect(result.cogs_breakdown["700_sub_other"]).to eq(BigDecimal("0"))
      end
    end

    describe "COGS sum check" do
      it "COGS categories sum to grand_non_burdened_total + 200_engineering + cogs_job_costs + countertop_quote, not to burdened_total" do
        estimate.update!(
          profit_overhead_percent: BigDecimal("10"),
          pm_supervision_percent:  BigDecimal("4"),
          countertop_quote:        BigDecimal("500.00"),
          install_travel_qty:      BigDecimal("2"),
          installer_crew_size:     2,
          per_diem_qty:            BigDecimal("3"),
          per_diem_rate:           BigDecimal("65.00"),
          delivery_qty:            BigDecimal("0")
        )
        result = described_class.new(preloaded_estimate).call

        cogs_sum      = result.cogs_breakdown.values.sum
        engineering   = result.cogs_breakdown["200_engineering"]
        # Job costs that appear in COGS 400 (install_travel, per_diem, hotel, airfare — NOT delivery)
        cogs_job_costs = result.job_level_costs[:install_travel] +
                         result.job_level_costs[:per_diem] +
                         result.job_level_costs[:hotel] +
                         result.job_level_costs[:airfare]

        # Positive assertion: COGS sum = grand_non_burdened_total + engineering + cogs_job_costs + countertop
        # Engineering (200) is derived from grand_non_burdened_total and added separately to COGS.
        expected = result.grand_non_burdened_total + engineering + cogs_job_costs +
                   result.cogs_breakdown["600_countertops"]
        expect(cogs_sum).to eq(expected)

        # COGS sum must NOT equal the burdened_total (selling price != cost structure)
        expect(cogs_sum).not_to eq(result.burdened_total)
      end
    end
  end

  # -----------------------------------------------------------------------
  # SPEC-012: AC-8 — tax_exempt flag affects cost_with_tax only
  # -----------------------------------------------------------------------

  describe "#call with tax_exempt: true (AC-8)" do
    let(:tax_rate) { BigDecimal("0.10") }
    let!(:mat) { create(:material, default_price: BigDecimal("100.00")) }

    let(:taxable_estimate) do
      create(:estimate,
             profit_overhead_percent: BigDecimal("10"),
             pm_supervision_percent:  BigDecimal("4"),
             tax_rate:                tax_rate,
             tax_exempt:              false,
             installer_crew_size:     2,
             install_travel_qty:      BigDecimal("1"),
             delivery_qty:            BigDecimal("2"),
             delivery_rate:           BigDecimal("400.00"),
             per_diem_qty:            BigDecimal("0"),
             per_diem_rate:           BigDecimal("65.00"),
             hotel_qty:               BigDecimal("0"),
             airfare_qty:             BigDecimal("0"),
             countertop_quote:        BigDecimal("0"))
    end

    let(:exempt_estimate) do
      create(:estimate,
             profit_overhead_percent: BigDecimal("10"),
             pm_supervision_percent:  BigDecimal("4"),
             tax_rate:                tax_rate,
             tax_exempt:              true,
             installer_crew_size:     2,
             install_travel_qty:      BigDecimal("1"),
             delivery_qty:            BigDecimal("2"),
             delivery_rate:           BigDecimal("400.00"),
             per_diem_qty:            BigDecimal("0"),
             per_diem_rate:           BigDecimal("65.00"),
             hotel_qty:               BigDecimal("0"),
             airfare_qty:             BigDecimal("0"),
             countertop_quote:        BigDecimal("0"))
    end

    let!(:taxable_em) { create(:estimate_material, estimate: taxable_estimate, material: mat, quote_price: BigDecimal("100.00")) }
    let!(:exempt_em)  { create(:estimate_material, estimate: exempt_estimate,  material: mat, quote_price: BigDecimal("100.00")) }

    let!(:taxable_li) do
      create(:line_item, estimate: taxable_estimate,
             exterior_material_id: taxable_em.id,
             exterior_qty: BigDecimal("1.0"),
             quantity: BigDecimal("1"))
    end

    let!(:exempt_li) do
      create(:line_item, estimate: exempt_estimate,
             exterior_material_id: exempt_em.id,
             exterior_qty: BigDecimal("1.0"),
             quantity: BigDecimal("1"))
    end

    let(:taxable_result) { described_class.new(Estimate.includes(:line_items).find(taxable_estimate.id)).call }
    let(:exempt_result)  { described_class.new(Estimate.includes(:line_items).find(exempt_estimate.id)).call }

    it "cost_with_tax differs between taxable and tax_exempt estimate materials" do
      expect(taxable_em.cost_with_tax).to eq(BigDecimal("110.00"))
      expect(exempt_em.cost_with_tax).to eq(BigDecimal("100.00"))
    end

    it "burdened_total differs between taxable and tax_exempt estimates" do
      # tax adds to material cost, which flows into burdened_total
      expect(exempt_result.burdened_total).not_to eq(taxable_result.burdened_total)
    end

    it "job_level_costs are identical for taxable and tax_exempt estimates" do
      taxable_result.job_level_costs.each_key do |key|
        expect(exempt_result.job_level_costs[key]).to eq(taxable_result.job_level_costs[key]),
          "expected job_level_costs[#{key}] to be equal but taxable=#{taxable_result.job_level_costs[key]} exempt=#{exempt_result.job_level_costs[key]}"
      end
    end

    it "burden_multiplier is identical for taxable and tax_exempt estimates" do
      expect(exempt_result.burden_multiplier).to eq(taxable_result.burden_multiplier)
    end
  end

  describe "#call labor_hours_summary and man_days_install" do
    let!(:li1) do
      create(:line_item, estimate: estimate,
             detail_hrs:   BigDecimal("2.0"),
             install_hrs:  BigDecimal("8.0"),
             quantity:     BigDecimal("1"))
    end

    let!(:li2) do
      create(:line_item, estimate: estimate,
             detail_hrs:   BigDecimal("1.0"),
             install_hrs:  BigDecimal("8.0"),
             quantity:     BigDecimal("2"))
    end

    subject(:result) { described_class.new(preloaded_estimate).call }

    it "sums labor hours across all line items (accounting for quantity)" do
      # li1: 2.0 * 1 = 2.0 detail; li2: 1.0 * 2 = 2.0 detail; total = 4.0
      expect(result.labor_hours_summary["detail"]).to eq(BigDecimal("4.0"))
    end

    it "computes man_days_install as total install hours / 8" do
      # li1: 8.0 * 1 = 8.0; li2: 8.0 * 2 = 16.0; total = 24.0; man_days = 24.0 / 8 = 3.0
      expect(result.man_days_install).to eq(BigDecimal("3.0"))
    end
  end

  # -----------------------------------------------------------------------
  # SPEC-012: Reference estimate fixture — AC-10
  # -----------------------------------------------------------------------
  # Synthetic reference estimate with round numbers.
  # Line item: 2 units, 1 sheet of exterior @ $100/sheet, 2 hrs detail @ $20/hr, 4 hrs install @ $23/hr
  # Job costs: 1 install trip (2 crew, round trip), 3 delivery trips @ $400, 2 per diem days (2 crew) @ $65
  # Settings: profit_overhead = 10%, pm_supervision = 4%

  describe "#call reference estimate fixture (AC-10)" do
    let(:ref_estimate) do
      create(:estimate,
             profit_overhead_percent: BigDecimal("10"),
             pm_supervision_percent:  BigDecimal("4"),
             tax_rate:                BigDecimal("0"),
             tax_exempt:              false,
             installer_crew_size:     2,
             install_travel_qty:      BigDecimal("1"),
             delivery_qty:            BigDecimal("3"),
             delivery_rate:           BigDecimal("400.00"),
             per_diem_qty:            BigDecimal("2"),
             per_diem_rate:           BigDecimal("65.00"),
             hotel_qty:               BigDecimal("0"),
             airfare_qty:             BigDecimal("0"),
             countertop_quote:        BigDecimal("0"))
    end

    let!(:ref_material) { create(:material, default_price: BigDecimal("100.00")) }
    let!(:ref_em)       { create(:estimate_material, estimate: ref_estimate, material: ref_material, quote_price: BigDecimal("100.00")) }
    let!(:ref_li) do
      create(:line_item, estimate: ref_estimate,
             exterior_material_id: ref_em.id,
             exterior_qty:         BigDecimal("1.0"),
             detail_hrs:           BigDecimal("2.0"),
             install_hrs:          BigDecimal("4.0"),
             quantity:             BigDecimal("2"))
    end

    subject(:result) do
      described_class.new(Estimate.includes(:line_items).find(ref_estimate.id)).call
    end

    # Expected math:
    # materials per unit = 1.0 * 100.00 = 100.00; subtotal_materials = 100.00 * 2 = 200.00
    # detail labor = 2.0 * $20 * 2 = 80.00
    # install labor = 4.0 * $23 * 2 = 184.00
    # non_burdened_total = 200 + 80 + 184 = 464.00
    # burden_multiplier = 1.10 * 1.04 = 1.144
    # install_travel = 1 * 2 * 0.67 * 2 = 2.68
    # delivery = 3 * 400 = 1200.00
    # per_diem = 2 * 65.00 * 2 = 260.00
    # job_costs_sum = 2.68 + 1200.00 + 260.00 = 1462.68
    # burdened_total = (464.00 * 1.144) + 1462.68 = 530.816 + 1462.68 = 1993.496

    it "computes grand_non_burdened_total correctly" do
      expect(result.grand_non_burdened_total).to eq(BigDecimal("464.00"))
    end

    it "computes burden_multiplier correctly" do
      expect(result.burden_multiplier).to eq(BigDecimal("1.144"))
    end

    it "computes install_travel_cost correctly" do
      mileage_rate = Rails.application.config.burden_constants[:mileage_rate]
      expected = BigDecimal("1") * BigDecimal("2") * mileage_rate * BigDecimal("2")
      expect(result.job_level_costs[:install_travel]).to eq(expected)
    end

    it "computes delivery_cost correctly" do
      expect(result.job_level_costs[:delivery]).to eq(BigDecimal("1200.00"))
    end

    it "computes per_diem_cost correctly" do
      expect(result.job_level_costs[:per_diem]).to eq(BigDecimal("260.00"))
    end

    it "computes burdened_total correctly to two decimal places" do
      mileage_rate = Rails.application.config.burden_constants[:mileage_rate]
      install_travel = BigDecimal("1") * BigDecimal("2") * mileage_rate * BigDecimal("2")
      job_costs_sum = install_travel + BigDecimal("1200.00") + BigDecimal("260.00")
      expected = (BigDecimal("464.00") * BigDecimal("1.144")) + job_costs_sum
      expect(result.burdened_total.round(2)).to eq(expected.round(2))
    end

    it "computes COGS 100_materials correctly" do
      expect(result.cogs_breakdown["100_materials"]).to eq(BigDecimal("200.00"))
    end

    it "computes COGS 300_shop_labor correctly (detail only in this fixture)" do
      expect(result.cogs_breakdown["300_shop_labor"]).to eq(BigDecimal("80.00"))
    end

    it "computes COGS 400_install correctly" do
      mileage_rate   = Rails.application.config.burden_constants[:mileage_rate]
      install_travel = BigDecimal("1") * BigDecimal("2") * mileage_rate * BigDecimal("2")
      install_labor  = BigDecimal("4.0") * BigDecimal("23.00") * BigDecimal("2")
      per_diem       = BigDecimal("2") * BigDecimal("65.00") * BigDecimal("2")
      expected       = install_labor + install_travel + per_diem
      expect(result.cogs_breakdown["400_install"]).to eq(expected)
    end
  end
end
