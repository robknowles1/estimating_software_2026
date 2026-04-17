require "rails_helper"

RSpec.describe EstimateTotalsCalculator do
  let(:estimate) do
    create(:estimate,
           profit_overhead_percent: BigDecimal("0"),
           pm_supervision_percent:  BigDecimal("0"),
           tax_rate:                BigDecimal("0"),
           tax_exempt:              false)
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
end
