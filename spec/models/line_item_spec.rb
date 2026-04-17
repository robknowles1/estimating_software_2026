require "rails_helper"

RSpec.describe LineItem, type: :model do
  subject(:line_item) { build(:line_item) }

  describe "associations" do
    it { is_expected.to belong_to(:estimate) }
    it { is_expected.to belong_to(:product).optional }

    %i[exterior interior interior2 back banding drawers pulls hinges slides].each do |slot|
      it { is_expected.to belong_to(:"#{slot}_material").class_name("EstimateMaterial").optional }
    end
  end

  describe "validations" do
    it { is_expected.to validate_presence_of(:description) }
    it { is_expected.to validate_presence_of(:unit) }
    it { is_expected.to validate_numericality_of(:quantity).is_greater_than(0) }
  end

  describe "material FK columns" do
    it "has exterior_material_id attribute" do
      expect(line_item).to respond_to(:exterior_material_id)
    end

    it "has banding_material_id attribute" do
      expect(line_item).to respond_to(:banding_material_id)
    end

    it "has slides_material_id attribute" do
      expect(line_item).to respond_to(:slides_material_id)
    end
  end

  describe "removed flat material columns" do
    it "does not respond to exterior_description" do
      expect(line_item).not_to respond_to(:exterior_description)
    end

    it "does not respond to exterior_unit_price" do
      expect(line_item).not_to respond_to(:exterior_unit_price)
    end

    it "does not respond to banding_unit_price" do
      expect(line_item).not_to respond_to(:banding_unit_price)
    end

    it "does not respond to locks_unit_price" do
      expect(line_item).not_to respond_to(:locks_unit_price)
    end
  end

  describe "optional product association" do
    it "is valid with product_id nil" do
      li = build(:line_item, product_id: nil)
      expect(li).to be_valid
    end
  end
end
