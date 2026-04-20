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

  describe "#material_ids_belong_to_estimate" do
    let(:estimate)       { create(:estimate) }
    let(:other_estimate) { create(:estimate) }
    let(:material)       { create(:material) }

    it "is valid when all material ids belong to the same estimate" do
      em = create(:estimate_material, estimate: estimate, material: material)
      li = build(:line_item, estimate: estimate, exterior_material_id: em.id)
      expect(li).to be_valid
    end

    it "is invalid when a material id belongs to a different estimate" do
      em_other = create(:estimate_material, estimate: other_estimate, material: material)
      li = build(:line_item, estimate: estimate, exterior_material_id: em_other.id)
      expect(li).to be_invalid
      expect(li.errors[:exterior_material_id]).not_to be_empty
    end

    it "is valid when all material id columns are nil" do
      li = build(:line_item, estimate: estimate)
      expect(li).to be_valid
    end

    it "marks only the offending column invalid when one slot is from a foreign estimate" do
      own_material   = create(:material, name: "Own Mat")
      other_material = create(:material, name: "Other Mat")
      em_own   = create(:estimate_material, estimate: estimate,       material: own_material)
      em_other = create(:estimate_material, estimate: other_estimate, material: other_material)
      li = build(:line_item, estimate: estimate,
                             exterior_material_id: em_own.id,
                             interior_material_id: em_other.id)
      expect(li).to be_invalid
      expect(li.errors[:interior_material_id]).not_to be_empty
      expect(li.errors[:exterior_material_id]).to be_empty
    end
  end
end
