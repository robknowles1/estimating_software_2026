require "rails_helper"

RSpec.describe LineItem, type: :model do
  subject(:line_item) { build(:line_item) }

  describe "associations" do
    it { is_expected.to belong_to(:estimate) }
    it { is_expected.to belong_to(:product).optional }
  end

  describe "validations" do
    it { is_expected.to validate_presence_of(:description) }
    it { is_expected.to validate_presence_of(:unit) }
    it { is_expected.to validate_numericality_of(:quantity).is_greater_than(0) }
  end

  describe "no material FK associations" do
    it "does not respond to exterior_material" do
      expect(line_item).not_to respond_to(:exterior_material)
    end

    it "does not respond to interior_material" do
      expect(line_item).not_to respond_to(:interior_material)
    end
  end

  describe "flat material columns" do
    it "has exterior_description column" do
      expect(line_item).to respond_to(:exterior_description)
    end

    it "has exterior_unit_price column" do
      expect(line_item).to respond_to(:exterior_unit_price)
    end

    it "has banding_unit_price column (flat per-unit, no qty)" do
      expect(line_item).to respond_to(:banding_unit_price)
    end

    it "has locks_unit_price column" do
      expect(line_item).to respond_to(:locks_unit_price)
    end

    it "has locks_description column" do
      expect(line_item).to respond_to(:locks_description)
    end
  end

  describe "optional product association" do
    it "is valid with product_id nil" do
      li = build(:line_item, product_id: nil)
      expect(li).to be_valid
    end
  end
end
