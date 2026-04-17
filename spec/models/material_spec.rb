require "rails_helper"

RSpec.describe Material, type: :model do
  subject(:material) { build(:material) }

  describe "validations" do
    it { is_expected.to validate_presence_of(:name) }
    it { is_expected.to validate_numericality_of(:default_price).is_greater_than_or_equal_to(0) }

    it "is invalid with a category outside the allowed list" do
      material.category = "unknown"
      expect(material).not_to be_valid
      expect(material.errors[:category]).to be_present
    end

    it "is valid with category sheet_good" do
      material.category = "sheet_good"
      expect(material).to be_valid
    end

    it "is valid with category hardware" do
      material.category = "hardware"
      expect(material).to be_valid
    end
  end

  describe "factory" do
    it "creates an active record with discarded_at nil" do
      m = create(:material)
      expect(m).to be_persisted
      expect(m.discarded_at).to be_nil
    end
  end

  describe ".active scope" do
    it "excludes soft-deleted records" do
      active    = create(:material)
      discarded = create(:material, discarded_at: 1.day.ago)

      expect(Material.active).to include(active)
      expect(Material.active).not_to include(discarded)
    end
  end

  describe ".search scope" do
    let!(:maple)    { create(:material, name: "Maple Plywood 3/4", description: "Premium grade") }
    let!(:hardware) { create(:material, name: "Door Hinge", description: "Maple finish hardware") }
    let!(:other)    { create(:material, name: "Pine Sheet", description: "Standard pine") }

    it "matches by name fragment (case-insensitive)" do
      results = Material.search("maple")
      expect(results).to include(maple)
      expect(results).not_to include(other)
    end

    it "matches by description fragment" do
      results = Material.search("maple")
      expect(results).to include(hardware)
    end

    it "is case-insensitive" do
      expect(Material.search("MAPLE")).to include(maple)
    end

    it "only returns active records" do
      maple.update!(discarded_at: Time.current)
      expect(Material.search("maple")).not_to include(maple)
    end
  end

  describe "#discard!" do
    context "when material has no estimate_materials rows" do
      it "sets discarded_at to the current time" do
        material = create(:material)
        expect(material.discard!).to be_truthy
        expect(material.reload.discarded_at).to be_present
      end
    end

    context "when material has associated estimate_materials rows" do
      it "returns false and adds a base error" do
        material = create(:material)
        estimate = create(:estimate)
        create(:estimate_material, estimate: estimate, material: material)

        result = material.discard!
        expect(result).to be false
        expect(material.errors[:base]).to be_present
        expect(material.reload.discarded_at).to be_nil
      end

      it "does not set discarded_at" do
        material = create(:material)
        estimate = create(:estimate)
        create(:estimate_material, estimate: estimate, material: material)

        material.discard!
        expect(material.reload.discarded_at).to be_nil
      end
    end
  end
end
