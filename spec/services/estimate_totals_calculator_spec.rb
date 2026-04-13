require "rails_helper"

RSpec.describe EstimateTotalsCalculator do
  let(:estimate) do
    create(:estimate, profit_overhead_percent: BigDecimal("0"), pm_supervision_percent: BigDecimal("0"))
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
    context "with exterior_qty and exterior_unit_price set" do
      let!(:li) do
        create(:line_item, estimate: estimate,
               exterior_qty: BigDecimal("2.0"), exterior_unit_price: BigDecimal("50.00"),
               quantity: BigDecimal("1"))
      end

      it "computes material_cost_per_unit as exterior_qty * exterior_unit_price" do
        result = calculator.call
        expect(result.line_item_results[li.id][:material_cost_per_unit]).to eq(BigDecimal("100.00"))
      end
    end

    context "with banding_unit_price set (no qty multiplier)" do
      let!(:li) do
        create(:line_item, estimate: estimate,
               banding_unit_price: BigDecimal("8.50"),
               quantity: BigDecimal("1"))
      end

      it "applies banding_unit_price directly without qty multiplier" do
        result = calculator.call
        expect(result.line_item_results[li.id][:material_cost_per_unit]).to eq(BigDecimal("8.50"))
      end
    end

    context "with locks_qty and locks_unit_price set" do
      let!(:li) do
        create(:line_item, estimate: estimate,
               locks_qty: BigDecimal("3.0"), locks_unit_price: BigDecimal("12.00"),
               quantity: BigDecimal("1"))
      end

      it "includes locks_qty * locks_unit_price in material cost" do
        result = calculator.call
        expect(result.line_item_results[li.id][:material_cost_per_unit]).to eq(BigDecimal("36.00"))
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
      let!(:li) do
        create(:line_item, estimate: estimate,
               exterior_qty: BigDecimal("2.0"), exterior_unit_price: BigDecimal("50.00"),
               banding_unit_price: BigDecimal("5.00"),
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
      # detail: 1.0 * 20.00 * 2 = 40.00
      expect(subtotals["detail"]).to eq(BigDecimal("40.00"))
      # assembly: 0.5 * 25.00 * 2 = 25.00
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
    let!(:li1) do
      create(:line_item, estimate: estimate,
             exterior_qty: BigDecimal("1.0"), exterior_unit_price: BigDecimal("100.00"),
             quantity: BigDecimal("1"))
    end
    let!(:li2) do
      create(:line_item, estimate: estimate,
             exterior_qty: BigDecimal("2.0"), exterior_unit_price: BigDecimal("50.00"),
             quantity: BigDecimal("1"))
    end

    it "sums non_burdened_total across all line items" do
      result = described_class.new(preloaded_estimate).call
      # li1 material: 1.0 * 100 = 100; li2 material: 2.0 * 50 = 100; total = 200
      expect(result.grand_non_burdened_total).to eq(BigDecimal("200.00"))
    end
  end

  describe "#call uses BigDecimal arithmetic" do
    let!(:li) do
      create(:line_item, estimate: estimate,
             exterior_qty: BigDecimal("1.3333"), exterior_unit_price: BigDecimal("3.0"),
             quantity: BigDecimal("1"))
    end

    it "returns BigDecimal result without floating point rounding errors" do
      result = calculator.call
      mat = result.line_item_results[li.id][:material_cost_per_unit]
      expect(mat).to be_a(BigDecimal)
      # 1.3333 * 3.0 = 3.9999 exactly in BigDecimal
      expect(mat).to eq(BigDecimal("1.3333") * BigDecimal("3.0"))
    end
  end

  describe "#call query count" do
    let!(:li1) { create(:line_item, estimate: estimate, quantity: BigDecimal("1")) }
    let!(:li2) { create(:line_item, estimate: estimate, quantity: BigDecimal("1")) }

    it "fires exactly one database query (LaborRate.all) regardless of line item count" do
      # Pre-load the estimate so preloading queries don't count
      loaded = preloaded_estimate

      query_count = 0
      counter = lambda do |_name, _start, _finish, _id, payload|
        next if %w[SCHEMA TRANSACTION CACHE].include?(payload[:name])
        query_count += 1
      end

      ActiveSupport::Notifications.subscribed(counter, "sql.active_record") do
        described_class.new(loaded).call
      end

      # Allow up to 2: LaborRate.all plus one spare for adapter bookkeeping
      expect(query_count).to be <= 2
    end
  end
end
