require "rails_helper"

RSpec.describe Product, type: :model do
  subject(:product) { build(:product) }

  describe "associations" do
    it { is_expected.to have_many(:line_items).dependent(:nullify) }
  end

  describe "validations" do
    it { is_expected.to validate_presence_of(:name) }
    it { is_expected.to validate_presence_of(:unit) }
  end

  describe "#apply_to(line_item)" do
    let(:product) do
      build(:product,
        name:                "MDF Base 2-door",
        unit:                "EA",
        exterior_description: "MDF sheet",
        exterior_unit_price:  BigDecimal("45.00"),
        exterior_qty:         BigDecimal("2.0"),
        interior_description: "Melamine",
        interior_unit_price:  BigDecimal("30.00"),
        interior_qty:         BigDecimal("1.5"),
        banding_description:  "Edge tape",
        banding_unit_price:   BigDecimal("5.00"),
        locks_description:    "Lock set",
        locks_unit_price:     BigDecimal("12.50"),
        locks_qty:            BigDecimal("2.0"),
        detail_hrs:           BigDecimal("0.75"),
        mill_hrs:             BigDecimal("1.25"),
        assembly_hrs:         BigDecimal("0.50"),
        customs_hrs:          BigDecimal("0.00"),
        finish_hrs:           BigDecimal("0.25"),
        install_hrs:          BigDecimal("0.10"),
        other_material_cost:  BigDecimal("8.00"),
        equipment_hrs:        BigDecimal("0.50"),
        equipment_rate:       BigDecimal("25.00"))
    end

    let(:line_item) { build(:line_item) }

    before { product.apply_to(line_item) }

    it "copies exterior_description" do
      expect(line_item.exterior_description).to eq("MDF sheet")
    end

    it "copies exterior_unit_price" do
      expect(line_item.exterior_unit_price).to eq(BigDecimal("45.00"))
    end

    it "copies exterior_qty" do
      expect(line_item.exterior_qty).to eq(BigDecimal("2.0"))
    end

    it "copies interior description and price" do
      expect(line_item.interior_description).to eq("Melamine")
      expect(line_item.interior_unit_price).to eq(BigDecimal("30.00"))
    end

    it "copies banding description and unit_price" do
      expect(line_item.banding_description).to eq("Edge tape")
      expect(line_item.banding_unit_price).to eq(BigDecimal("5.00"))
    end

    it "does not assign banding_qty (banding has no qty column)" do
      li = build(:line_item)
      expect { product.apply_to(li) }.not_to raise_error
      expect(li.respond_to?(:banding_qty)).to be(false)
    end

    it "copies locks description, unit_price, and qty" do
      expect(line_item.locks_description).to eq("Lock set")
      expect(line_item.locks_unit_price).to eq(BigDecimal("12.50"))
      expect(line_item.locks_qty).to eq(BigDecimal("2.0"))
    end

    it "copies all six labor hour fields" do
      expect(line_item.detail_hrs).to eq(BigDecimal("0.75"))
      expect(line_item.mill_hrs).to eq(BigDecimal("1.25"))
      expect(line_item.assembly_hrs).to eq(BigDecimal("0.50"))
      expect(line_item.customs_hrs).to eq(BigDecimal("0.00"))
      expect(line_item.finish_hrs).to eq(BigDecimal("0.25"))
      expect(line_item.install_hrs).to eq(BigDecimal("0.10"))
    end

    it "copies other_material_cost" do
      expect(line_item.other_material_cost).to eq(BigDecimal("8.00"))
    end

    it "copies equipment_hrs and equipment_rate" do
      expect(line_item.equipment_hrs).to eq(BigDecimal("0.50"))
      expect(line_item.equipment_rate).to eq(BigDecimal("25.00"))
    end

    it "copies unit" do
      expect(line_item.unit).to eq("EA")
    end

    it "does not save the line item" do
      li = build(:line_item)
      product.apply_to(li)
      expect(li).to be_new_record
    end

    it "does not assign product_id (controller responsibility)" do
      li = build(:line_item)
      product.apply_to(li)
      expect(li.product_id).to be_nil
    end
  end
end
