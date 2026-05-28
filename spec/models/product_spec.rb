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
        name:               "MDF Base 2-door",
        unit:               "EA",
        exterior_qty:       BigDecimal("2.0"),
        interior_qty:       BigDecimal("1.5"),
        interior2_qty:      BigDecimal("0.5"),
        back_qty:           BigDecimal("1.0"),
        drawers_qty:        BigDecimal("3.0"),
        pulls_qty:          BigDecimal("2.0"),
        hinges_qty:         BigDecimal("4.0"),
        slides_qty:         BigDecimal("2.0"),
        locks_qty:          BigDecimal("1.0"),
        detail_hrs:         BigDecimal("0.75"),
        mill_hrs:           BigDecimal("1.25"),
        assembly_hrs:       BigDecimal("0.50"),
        customs_hrs:        BigDecimal("0.00"),
        finish_hrs:         BigDecimal("0.25"),
        install_hrs:        BigDecimal("0.10"),
        other_material_cost: BigDecimal("8.00"),
        equipment_hrs:      BigDecimal("0.50"),
        equipment_rate:     BigDecimal("25.00"))
    end

    let(:line_item) { build(:line_item) }

    before { product.apply_to(line_item) }

    it "copies exterior_qty" do
      expect(line_item.exterior_qty).to eq(BigDecimal("2.0"))
    end

    it "copies interior_qty" do
      expect(line_item.interior_qty).to eq(BigDecimal("1.5"))
    end

    it "copies interior2_qty" do
      expect(line_item.interior2_qty).to eq(BigDecimal("0.5"))
    end

    it "copies back_qty" do
      expect(line_item.back_qty).to eq(BigDecimal("1.0"))
    end

    it "copies drawers_qty" do
      expect(line_item.drawers_qty).to eq(BigDecimal("3.0"))
    end

    it "copies pulls_qty" do
      expect(line_item.pulls_qty).to eq(BigDecimal("2.0"))
    end

    it "copies hinges_qty" do
      expect(line_item.hinges_qty).to eq(BigDecimal("4.0"))
    end

    it "copies slides_qty" do
      expect(line_item.slides_qty).to eq(BigDecimal("2.0"))
    end

    it "copies locks_qty" do
      expect(line_item.locks_qty).to eq(BigDecimal("1.0"))
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

    it "does not set any _material_id on the line item" do
      %i[exterior interior interior2 back banding drawers pulls hinges slides].each do |slot|
        expect(line_item.public_send(:"#{slot}_material_id")).to be_nil
      end
    end

    it "does not raise NoMethodError for _unit_price or _description (those columns are gone)" do
      li = build(:line_item)
      expect { product.apply_to(li) }.not_to raise_error
      expect(li).not_to respond_to(:exterior_unit_price)
      expect(li).not_to respond_to(:exterior_description)
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

  describe "SLOT_CODE_COLUMNS constant" do
    it "lists all ten slot code attribute symbols" do
      expected = %i[
        exterior_slot_code interior_slot_code interior2_slot_code back_slot_code
        banding_slot_code drawers_slot_code pulls_slot_code hinges_slot_code
        slides_slot_code locks_slot_code
      ]
      expect(Product::SLOT_CODE_COLUMNS).to eq(expected)
    end
  end

  describe "slot code attributes" do
    it "is valid with all slot_code columns nil" do
      product = build(:product)
      Product::SLOT_CODE_COLUMNS.each { |col| product.public_send(:"#{col}=", nil) }
      expect(product).to be_valid
    end

    it "is valid and persists pulls_slot_code value" do
      product = create(:product, pulls_slot_code: "PULL1")
      expect(product.reload.pulls_slot_code).to eq("PULL1")
    end
  end
end
