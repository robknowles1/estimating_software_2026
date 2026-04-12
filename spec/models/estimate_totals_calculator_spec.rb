require "rails_helper"

RSpec.describe EstimateTotalsCalculator do
  let(:estimate)    { create(:estimate, :skip_material_seeding, profit_overhead_percent: 20, pm_supervision_percent: 10, tax_rate: 0) }
  let(:ext_mat)     { create(:material, estimate: estimate, slot_key: "EXT1", category: "sheet_good", quote_price: 50, cost_with_tax: 50) }
  let(:locks_mat)   { create(:material, estimate: estimate, slot_key: "LOCKS", category: "hardware", quote_price: 10, cost_with_tax: 10) }
  let!(:detail_rate)   { create(:labor_rate, labor_category: "detail",   hourly_rate: 65) }
  let!(:mill_rate)     { create(:labor_rate, labor_category: "mill",     hourly_rate: 100) }
  let!(:assembly_rate) { create(:labor_rate, labor_category: "assembly", hourly_rate: 45) }
  let!(:customs_rate)  { create(:labor_rate, labor_category: "customs",  hourly_rate: 65) }
  let!(:finish_rate)   { create(:labor_rate, labor_category: "finish",   hourly_rate: 75) }
  let!(:install_rate)  { create(:labor_rate, labor_category: "install",  hourly_rate: 80) }

  # Helper: reload estimate via includes so materials association is freshly loaded
  def fresh(est)
    Estimate.includes(
      :materials,
      line_items: [
        :exterior_material, :interior_material, :interior2_material,
        :back_material, :banding_material, :drawers_material,
        :pulls_material, :hinges_material, :slides_material
      ]
    ).find(est.id)
  end

  describe "#call" do
    context "with one line item with known values" do
      let!(:line_item) do
        locks_mat # ensure LOCKS material is persisted
        create(:line_item, estimate: estimate,
               quantity: 2,
               exterior_material_id: ext_mat.id, exterior_qty: 3,
               locks_qty: 5,
               other_material_cost: 10,
               detail_hrs: 1, mill_hrs: 0, assembly_hrs: 0,
               customs_hrs: 0, finish_hrs: 0, install_hrs: 0)
      end

      it "calculates material_cost_per_unit correctly" do
        result = EstimateTotalsCalculator.new(fresh(estimate)).call
        r = result.line_item_results[line_item.id]
        # 3 * 50 (exterior) + 5 * 10 (locks) + 10 (other) = 150 + 50 + 10 = 210
        expect(r[:material_cost_per_unit]).to eq(BigDecimal("210"))
      end

      it "calculates subtotal_materials as material_cost_per_unit * quantity" do
        result = EstimateTotalsCalculator.new(fresh(estimate)).call
        r = result.line_item_results[line_item.id]
        expect(r[:subtotal_materials]).to eq(BigDecimal("420"))
      end

      it "calculates labor subtotals correctly" do
        result = EstimateTotalsCalculator.new(fresh(estimate)).call
        r = result.line_item_results[line_item.id]
        # detail: 1 hr * 65/hr * 2 qty = 130
        expect(r[:labor_subtotals]["detail"]).to eq(BigDecimal("130"))
      end

      it "calculates non_burdened_total correctly" do
        result = EstimateTotalsCalculator.new(fresh(estimate)).call
        r = result.line_item_results[line_item.id]
        # 420 (materials) + 130 (detail labor) + 0 (other labor) + 0 (equipment) = 550
        expect(r[:non_burdened_total]).to eq(BigDecimal("550"))
      end

      it "sums to grand_non_burdened_total" do
        result = EstimateTotalsCalculator.new(fresh(estimate)).call
        expect(result.grand_non_burdened_total).to eq(BigDecimal("550"))
      end
    end

    it "treats nil material assignments as zero" do
      li = create(:line_item, estimate: estimate, quantity: 1, exterior_material_id: nil, exterior_qty: 5)
      result = EstimateTotalsCalculator.new(fresh(estimate)).call
      expect(result.line_item_results[li.id][:material_cost_per_unit]).to eq(BigDecimal("0"))
    end

    it "includes locks_qty with LOCKS slot price" do
      locks_mat
      li = create(:line_item, estimate: estimate, quantity: 1, locks_qty: 4)
      result = EstimateTotalsCalculator.new(fresh(estimate)).call
      # 4 * 10 = 40
      expect(result.line_item_results[li.id][:material_cost_per_unit]).to eq(BigDecimal("40"))
    end

    it "includes other_material_cost" do
      li = create(:line_item, estimate: estimate, quantity: 1, other_material_cost: 99)
      result = EstimateTotalsCalculator.new(fresh(estimate)).call
      expect(result.line_item_results[li.id][:material_cost_per_unit]).to eq(BigDecimal("99"))
    end

    it "uses BigDecimal — no floating point errors" do
      mat = create(:material, estimate: estimate, slot_key: "EXT_TEST", category: "sheet_good", quote_price: "0.1", cost_with_tax: "0.1")
      li = create(:line_item, estimate: estimate, quantity: 1, exterior_qty: 3,
                  exterior_material_id: mat.id)
      result = EstimateTotalsCalculator.new(fresh(estimate)).call
      expect(result.line_item_results[li.id][:material_cost_per_unit]).to eq(BigDecimal("0.3"))
    end

    it "calculates burden_multiplier correctly" do
      # (1 + 20/100) * (1 + 10/100) = 1.2 * 1.1 = 1.32
      result = EstimateTotalsCalculator.new(fresh(estimate)).call
      expect(result.burden_multiplier).to eq(BigDecimal("1.32"))
    end

    it "fires at most 3 queries regardless of line item count" do
      # Create several line items
      3.times { create(:line_item, estimate: estimate) }
      fresh_estimate = Estimate.includes(
        :materials,
        line_items: [
          :exterior_material, :interior_material, :interior2_material,
          :back_material, :banding_material, :drawers_material,
          :pulls_material, :hinges_material, :slides_material
        ]
      ).find(estimate.id)

      query_count = 0
      counter = ->(*, **) { query_count += 1 }
      ActiveSupport::Notifications.subscribed(counter, "sql.active_record") do
        EstimateTotalsCalculator.new(fresh_estimate).call
      end
      # Should fire: 1 for materials (already loaded), 1 for labor_rates
      expect(query_count).to be <= 3
    end
  end
end
