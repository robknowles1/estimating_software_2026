require "rails_helper"

RSpec.describe EstimateTotalsCalculator do
  let(:estimate) { create(:estimate, :skip_material_seeding, profit_overhead_percent: 0, pm_supervision_percent: 0) }
  let(:section) { create(:estimate_section, estimate: estimate, quantity: 5) }

  let(:pl_material) do
    create(:estimate_material, estimate: estimate, category: "pl", slot_number: 1, price_per_unit: BigDecimal("50.00"))
  end

  let!(:assembly_rate) { create(:labor_rate, labor_category: "assembly", hourly_rate: BigDecimal("25.00")) }

  subject(:calculator) { described_class.new(preloaded_estimate) }

  let(:preloaded_estimate) do
    Estimate.includes(estimate_sections: { line_items: :estimate_material }).find(estimate.id)
  end

  describe "#call with a material line item" do
    before do
      create(:line_item,
        estimate_section: section,
        line_item_category: "material",
        description: "Exterior Sheet Good",
        estimate_material: pl_material,
        component_quantity: BigDecimal("0.32"))
    end

    it "returns correct non-burdened subtotal for the section" do
      result = calculator.call
      # 0.32 × 5 × 50.00 = 80.00
      expect(result.section_subtotals[section.id][:non_burdened]).to eq(BigDecimal("80.00"))
    end
  end

  describe "#call with a labor line item" do
    before do
      create(:line_item,
        estimate_section: section,
        line_item_category: "labor",
        description: "Assembly Labor",
        labor_category: "assembly",
        hours_per_unit: BigDecimal("0.375"))
    end

    it "returns correct non-burdened subtotal for the section" do
      result = calculator.call
      # 0.375 × 5 × 25.00 = 46.875
      expect(result.section_subtotals[section.id][:non_burdened]).to eq(BigDecimal("46.875"))
    end
  end

  describe "#call returns correct non-burdened and burdened totals per section" do
    before do
      create(:line_item,
        estimate_section: section,
        line_item_category: "material",
        description: "Exterior",
        estimate_material: pl_material,
        component_quantity: BigDecimal("0.32"))
      create(:line_item,
        estimate_section: section,
        line_item_category: "labor",
        description: "Assembly",
        labor_category: "assembly",
        hours_per_unit: BigDecimal("0.375"))
    end

    context "with no burden factors" do
      it "returns non-burdened equal to material + labor cost" do
        result = calculator.call
        # material: 0.32 × 5 × 50 = 80; labor: 0.375 × 5 × 25 = 46.875; total = 126.875
        expect(result.section_subtotals[section.id][:non_burdened]).to eq(BigDecimal("126.875"))
      end

      it "returns burdened equal to non-burdened when no burden factors" do
        result = calculator.call
        expect(result.section_subtotals[section.id][:burdened]).to eq(BigDecimal("126.875"))
      end
    end

    context "with profit_overhead_percent = 20" do
      before { estimate.update!(profit_overhead_percent: 20) }

      it "applies the burden multiplier to non-burdened total" do
        result = calculator.call
        # 126.875 × 1.20 = 152.25
        expect(result.section_subtotals[section.id][:burdened]).to eq(BigDecimal("152.25"))
      end
    end

    context "with multiplicative burden (profit 20% and pm 10%)" do
      before { estimate.update!(profit_overhead_percent: 20, pm_supervision_percent: 10) }

      it "applies both multipliers multiplicatively" do
        result = calculator.call
        # 126.875 × 1.20 × 1.10 = 167.475
        expect(result.section_subtotals[section.id][:burdened]).to eq(BigDecimal("167.475"))
      end
    end
  end

  describe "#call grand_total_non_burdened sums across multiple sections" do
    let(:section_2) { create(:estimate_section, estimate: estimate, quantity: 3) }
    let(:pl_material_2) do
      create(:estimate_material, estimate: estimate, category: "pl", slot_number: 2, price_per_unit: BigDecimal("40.00"))
    end

    before do
      create(:line_item,
        estimate_section: section,
        line_item_category: "material",
        description: "Section 1 Material",
        estimate_material: pl_material,
        component_quantity: BigDecimal("1.0"))

      create(:line_item,
        estimate_section: section_2,
        line_item_category: "material",
        description: "Section 2 Material",
        estimate_material: pl_material_2,
        component_quantity: BigDecimal("1.0"))
    end

    it "sums non-burdened across all sections" do
      result = calculator.call
      # section1: 1 × 5 × 50 = 250; section2: 1 × 3 × 40 = 120; total = 370
      expect(result.grand_total_non_burdened).to eq(BigDecimal("370.00"))
    end
  end

  describe "#call alternate_total and buy_out_total are excluded from grand_total" do
    before do
      create(:line_item,
        estimate_section: section,
        line_item_category: "material",
        description: "Cabinet material",
        estimate_material: pl_material,
        component_quantity: BigDecimal("1.0"))
      create(:line_item,
        estimate_section: section,
        line_item_category: "alternate",
        description: "Alternate item",
        freeform_quantity: BigDecimal("1"),
        unit_cost: BigDecimal("500.00"),
        markup_percent: BigDecimal("10.0"))
      create(:line_item,
        estimate_section: section,
        line_item_category: "buy_out",
        description: "Buy-out item",
        freeform_quantity: BigDecimal("2"),
        unit_cost: BigDecimal("100.00"),
        markup_percent: BigDecimal("5.0"))
    end

    it "excludes alternate and buy_out from grand_total_non_burdened" do
      result = calculator.call
      # only material: 1 × 5 × 50 = 250
      expect(result.grand_total_non_burdened).to eq(BigDecimal("250.00"))
    end

    it "correctly totals the alternate items" do
      result = calculator.call
      expect(result.alternate_total[:non_burdened]).to eq(BigDecimal("500.00"))
      expect(result.alternate_total[:sell]).to eq(BigDecimal("550.00"))
    end

    it "correctly totals the buy-out items" do
      result = calculator.call
      expect(result.buy_out_total[:cost]).to eq(BigDecimal("200.00"))
      expect(result.buy_out_total[:sell]).to eq(BigDecimal("210.00"))
    end
  end

  describe "#call with preloaded associations does not fire additional queries" do
    before do
      create(:line_item,
        estimate_section: section,
        line_item_category: "material",
        description: "Material",
        estimate_material: pl_material,
        component_quantity: BigDecimal("1.0"))
    end

    it "completes without firing per-item queries for labor rates or materials" do
      # Force lazy lets to evaluate before we start counting queries.
      # Without this, the Estimate.includes(...).find(...) preload fires inside
      # the subscribed block and inflates the count.
      preloaded_estimate

      # Verify that calling the calculator on preloaded data does not fire per-item queries.
      # Only LaborRate.all (1 query) is expected — everything else is already in memory.
      # The key invariant: query count is O(1), not O(n) in the number of line items.
      query_count = 0
      counter = lambda do |_name, _start, _finish, _id, payload|
        next if %w[SCHEMA TRANSACTION CACHE].include?(payload[:name])
        query_count += 1
      end

      ActiveSupport::Notifications.subscribed(counter, "sql.active_record") do
        calculator.call
      end

      # Allow up to 2: LaborRate.all plus one spare for any adapter bookkeeping.
      expect(query_count).to be <= 2
    end
  end
end
