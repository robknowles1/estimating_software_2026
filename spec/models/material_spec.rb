require "rails_helper"

RSpec.describe Material, type: :model do
  subject(:material) { build(:material) }

  describe "associations" do
    it { is_expected.to belong_to(:estimate) }
  end

  describe "validations" do
    it { is_expected.to validate_presence_of(:slot_key) }
    it { is_expected.to validate_numericality_of(:quote_price).is_greater_than_or_equal_to(0) }

    describe "uniqueness of slot_key scoped to estimate" do
      let(:estimate) { create(:estimate, :skip_material_seeding) }

      it "is invalid when slot_key is duplicated within the same estimate" do
        create(:material, estimate: estimate, slot_key: "PL1")
        dup = build(:material, estimate: estimate, slot_key: "PL1")
        expect(dup).not_to be_valid
        expect(dup.errors[:slot_key]).to be_present
      end

      it "is valid when the same slot_key belongs to a different estimate" do
        other_estimate = create(:estimate, :skip_material_seeding)
        create(:material, estimate: estimate, slot_key: "PL1")
        different = build(:material, estimate: other_estimate, slot_key: "PL1")
        expect(different).to be_valid
      end
    end

    describe "category inclusion" do
      it "is valid with sheet_good" do
        m = build(:material, category: "sheet_good")
        expect(m).to be_valid
      end

      it "is valid with hardware" do
        m = build(:material, category: "hardware")
        expect(m).to be_valid
      end

      it "is invalid with an unrecognised category" do
        m = build(:material, category: "other")
        expect(m).not_to be_valid
      end
    end
  end

  describe "Material::SLOTS" do
    it "contains exactly 50 slot definitions" do
      expect(Material::SLOTS.length).to eq(50)
    end

    it "includes PL1 through PL6 as sheet_goods" do
      pl_slots = Material::SLOTS.select { |s| s[:slot_key].match?(/\APL\d\z/) }
      expect(pl_slots.map { |s| s[:category] }.uniq).to eq(%w[sheet_good])
      expect(pl_slots.length).to eq(6)
    end

    it "includes LOCKS as hardware" do
      locks = Material::SLOTS.find { |s| s[:slot_key] == "LOCKS" }
      expect(locks).not_to be_nil
      expect(locks[:category]).to eq("hardware")
    end

    it "includes BALTIC_DOVETAIL as hardware" do
      bd = Material::SLOTS.find { |s| s[:slot_key] == "BALTIC_DOVETAIL" }
      expect(bd).not_to be_nil
      expect(bd[:category]).to eq("hardware")
    end

    it "all slot_keys are unique" do
      keys = Material::SLOTS.map { |s| s[:slot_key] }
      expect(keys.uniq.length).to eq(keys.length)
    end
  end

  describe "#compute_cost_with_tax (before_save callback)" do
    let(:estimate) { create(:estimate, :skip_material_seeding, tax_rate: BigDecimal("0.08"), tax_exempt: false) }

    context "when estimate is not tax_exempt" do
      it "sets cost_with_tax = quote_price * (1 + tax_rate)" do
        material = create(:material, estimate: estimate, quote_price: BigDecimal("100.00"))
        expected = BigDecimal("100.00") * (BigDecimal("1") + BigDecimal("0.08"))
        expect(material.cost_with_tax).to eq(expected)
      end

      it "recalculates when quote_price is updated and saved" do
        material = create(:material, estimate: estimate, quote_price: BigDecimal("100.00"))
        material.update!(quote_price: BigDecimal("200.00"))
        expected = BigDecimal("200.00") * BigDecimal("1.08")
        expect(material.reload.cost_with_tax).to eq(expected)
      end
    end

    context "when estimate is tax_exempt" do
      let(:exempt_estimate) { create(:estimate, :skip_material_seeding, tax_rate: BigDecimal("0.08"), tax_exempt: true) }

      it "sets cost_with_tax equal to quote_price (no tax applied)" do
        material = create(:material, estimate: exempt_estimate, quote_price: BigDecimal("75.00"))
        expect(material.cost_with_tax).to eq(BigDecimal("75.00"))
      end
    end
  end

  describe "#display_label" do
    it "returns the slot_key when no label is defined" do
      m = build(:material, slot_key: "PL1")
      expect(m.display_label).to eq("PL1")
    end

    it "returns the label when a label override is defined in SLOTS" do
      # QTR_MEL has label: '1/4" MEL'
      m = build(:material, slot_key: "QTR_MEL")
      expect(m.display_label).to eq('1/4" MEL')
    end
  end
end
