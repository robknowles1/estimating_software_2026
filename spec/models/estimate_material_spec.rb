require "rails_helper"

RSpec.describe EstimateMaterial, type: :model do
  let(:estimate) { create(:estimate, :skip_material_seeding) }

  subject(:material) do
    build(:estimate_material, estimate: estimate, category: "pl", slot_number: 1)
  end

  describe "validations" do
    it { is_expected.to validate_presence_of(:category) }
    it { is_expected.to validate_presence_of(:slot_number) }
    it { is_expected.to validate_numericality_of(:price_per_unit).is_greater_than_or_equal_to(0) }

    it "validates slot_number in 1..6" do
      material.slot_number = 7
      expect(material).not_to be_valid
    end

    it "accepts slot_number of 1" do
      material.slot_number = 1
      expect(material).to be_valid
    end

    it "accepts slot_number of 6" do
      material.slot_number = 6
      expect(material).to be_valid
    end

    it "rejects slot_number of 0" do
      material.slot_number = 0
      expect(material).not_to be_valid
    end

    it "validates uniqueness of [estimate_id, category, slot_number]" do
      create(:estimate_material, estimate: estimate, category: "pl", slot_number: 1)
      duplicate = build(:estimate_material, estimate: estimate, category: "pl", slot_number: 1)
      expect(duplicate).not_to be_valid
    end

    it "allows same slot_number for different categories" do
      create(:estimate_material, estimate: estimate, category: "pl", slot_number: 1)
      other = build(:estimate_material, estimate: estimate, category: "pull", slot_number: 1)
      expect(other).to be_valid
    end
  end

  describe "#slot_label" do
    it "returns the category uppercased with slot number" do
      expect(material.slot_label).to eq("PL1")
    end

    it "returns correct label for pull category slot 3" do
      material.category = "pull"
      material.slot_number = 3
      expect(material.slot_label).to eq("PULL3")
    end
  end
end
