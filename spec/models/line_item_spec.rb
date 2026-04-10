require "rails_helper"

RSpec.describe LineItem, type: :model do
  let(:estimate) { create(:estimate, :skip_material_seeding) }
  let(:section) { create(:estimate_section, estimate: estimate, quantity: 5) }
  let(:material) { create(:estimate_material, estimate: estimate, category: "pl", slot_number: 1, price_per_unit: BigDecimal("50.00")) }

  subject(:line_item) { build(:line_item, estimate_section: section) }

  describe "validations" do
    it { is_expected.to validate_presence_of(:description) }

    it { is_expected.to validate_numericality_of(:markup_percent).is_greater_than_or_equal_to(0).allow_nil }
    it { is_expected.to validate_numericality_of(:unit_cost).is_greater_than_or_equal_to(0).allow_nil }
    it { is_expected.to validate_numericality_of(:component_quantity).is_greater_than_or_equal_to(0).allow_nil }
    it { is_expected.to validate_numericality_of(:hours_per_unit).is_greater_than_or_equal_to(0).allow_nil }
    it { is_expected.to validate_numericality_of(:freeform_quantity).is_greater_than_or_equal_to(0).allow_nil }

    it "validates line_item_category is in the allowed list" do
      line_item.line_item_category = "invalid"
      expect(line_item).not_to be_valid
    end

    it "is valid with line_item_category 'material'" do
      line_item.line_item_category = "material"
      expect(line_item).to be_valid
    end

    it "is valid with line_item_category 'labor'" do
      line_item.line_item_category = "labor"
      expect(line_item).to be_valid
    end
  end

  describe "#extended_cost for a material item" do
    subject(:item) do
      build(:line_item,
        estimate_section: section,
        line_item_category: "material",
        estimate_material: material,
        component_quantity: BigDecimal("0.32"))
    end

    it "returns component_quantity × section_quantity × material_price" do
      # 0.32 × 5 × 50.00 = 80.00
      expect(item.extended_cost).to eq(BigDecimal("80.00"))
    end

    it "returns 0 when estimate_material is nil" do
      item.estimate_material = nil
      expect(item.extended_cost).to eq(BigDecimal("0"))
    end

    it "returns 0 when component_quantity is nil" do
      item.component_quantity = nil
      expect(item.extended_cost).to eq(BigDecimal("0"))
    end
  end

  describe "#extended_cost for a labor item" do
    let!(:labor_rate) { create(:labor_rate, labor_category: "assembly", hourly_rate: BigDecimal("25.00")) }

    subject(:item) do
      build(:line_item,
        estimate_section: section,
        line_item_category: "labor",
        labor_category: "assembly",
        hours_per_unit: BigDecimal("0.375"))
    end

    it "returns hours_per_unit × section_quantity × labor_rate" do
      # 0.375 × 5 × 25.00 = 46.875
      expect(item.extended_cost).to eq(BigDecimal("46.875"))
    end

    it "returns 0 when hours_per_unit is nil" do
      item.hours_per_unit = nil
      expect(item.extended_cost).to eq(BigDecimal("0"))
    end

    it "returns 0 when labor_category is nil" do
      item.labor_category = nil
      expect(item.extended_cost).to eq(BigDecimal("0"))
    end
  end

  describe "#extended_cost for a buy-out item (legacy free-form path)" do
    subject(:item) do
      build(:line_item,
        estimate_section: section,
        line_item_category: "buy_out",
        freeform_quantity: BigDecimal("3"),
        unit_cost: BigDecimal("100.00"))
    end

    it "returns freeform_quantity × unit_cost" do
      # 3 × 100.00 = 300.00
      expect(item.extended_cost).to eq(BigDecimal("300.00"))
    end

    it "returns 0 when freeform_quantity is nil" do
      item.freeform_quantity = nil
      expect(item.extended_cost).to eq(BigDecimal("0"))
    end
  end

  describe "#sell_price for a buy-out item" do
    subject(:item) do
      build(:line_item,
        estimate_section: section,
        line_item_category: "buy_out",
        freeform_quantity: BigDecimal("2"),
        unit_cost: BigDecimal("100.00"),
        markup_percent: BigDecimal("10.0"))
    end

    it "returns extended_cost × (1 + markup_percent / 100)" do
      # extended = 200.00; sell = 200.00 × 1.10 = 220.00
      expect(item.sell_price).to eq(BigDecimal("220.00"))
    end

    it "equals extended_cost when markup_percent is 0" do
      item.markup_percent = BigDecimal("0")
      expect(item.sell_price).to eq(item.extended_cost)
    end
  end
end
