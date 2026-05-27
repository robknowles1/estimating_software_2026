require "rails_helper"

RSpec.describe EstimateMaterial, type: :model do
  describe "associations" do
    it { is_expected.to belong_to(:estimate) }
    it { is_expected.to belong_to(:material) }
  end

  describe "validations" do
    it { is_expected.to validate_numericality_of(:quote_price).is_greater_than_or_equal_to(0) }

    describe "short_code uniqueness" do
      it "is valid when short_code is blank" do
        em = build(:estimate_material, short_code: nil)
        expect(em).to be_valid
      end

      it "is valid when short_code is unique within the estimate" do
        estimate = create(:estimate)
        material1 = create(:material)
        material2 = create(:material)
        create(:estimate_material, estimate: estimate, material: material1, short_code: "PL1")
        em2 = build(:estimate_material, estimate: estimate, material: material2, short_code: "PL2")
        expect(em2).to be_valid
      end

      it "is invalid when two records on the same estimate share the same short_code (case-insensitive)" do
        estimate = create(:estimate)
        material1 = create(:material)
        material2 = create(:material)
        create(:estimate_material, estimate: estimate, material: material1, short_code: "PL1")
        em2 = build(:estimate_material, estimate: estimate, material: material2, short_code: "pl1")
        expect(em2).not_to be_valid
        expect(em2.errors[:short_code]).to be_present
      end

      it "allows two blank short_codes on the same estimate" do
        estimate = create(:estimate)
        material1 = create(:material)
        material2 = create(:material)
        em1 = create(:estimate_material, estimate: estimate, material: material1, short_code: nil)
        em2 = build(:estimate_material, estimate: estimate, material: material2, short_code: nil)
        expect(em1).to be_valid
        expect(em2).to be_valid
      end

      it "allows the same short_code on different estimates" do
        estimate1 = create(:estimate)
        estimate2 = create(:estimate)
        material1 = create(:material)
        material2 = create(:material)
        create(:estimate_material, estimate: estimate1, material: material1, short_code: "PL1")
        em2 = build(:estimate_material, estimate: estimate2, material: material2, short_code: "PL1")
        expect(em2).to be_valid
      end
    end

    describe "before_validation short_code strip" do
      it "strips leading/trailing whitespace from short_code" do
        em = build(:estimate_material, short_code: "  PL1  ")
        em.valid?
        expect(em.short_code).to eq("PL1")
      end

      it "converts a blank (spaces-only) short_code to nil" do
        em = build(:estimate_material, short_code: "   ")
        em.valid?
        expect(em.short_code).to be_nil
      end
    end

    describe ":role inclusion" do
      it "is valid when role is nil" do
        em = build(:estimate_material, role: nil)
        expect(em).to be_valid
      end

      it "is valid when role is a known value" do
        em = build(:estimate_material, role: "locks")
        expect(em).to be_valid
      end

      it "is invalid when role is an unknown value" do
        em = build(:estimate_material, role: "admin")
        expect(em).not_to be_valid
        expect(em.errors[:role]).to be_present
      end
    end

    it "enforces uniqueness of material_id scoped to estimate_id" do
      estimate = create(:estimate)
      material = create(:material)
      create(:estimate_material, estimate: estimate, material: material)

      duplicate = build(:estimate_material, estimate: estimate, material: material)
      expect(duplicate).not_to be_valid
      expect(duplicate.errors[:material_id]).to be_present
    end
  end

  describe "before_save :compute_cost_with_tax" do
    context "when estimate is not tax_exempt" do
      it "sets cost_with_tax = quote_price * (1 + tax_rate)" do
        estimate = create(:estimate, tax_rate: BigDecimal("0.13"), tax_exempt: false)
        material = create(:material, default_price: BigDecimal("100.00"))
        em = create(:estimate_material, estimate: estimate, material: material, quote_price: BigDecimal("100.00"))

        expected = BigDecimal("100.00") * (BigDecimal("1") + BigDecimal("0.13"))
        expect(em.cost_with_tax).to eq(expected)
      end
    end

    context "when estimate is tax_exempt" do
      it "sets cost_with_tax = quote_price" do
        estimate = create(:estimate, tax_exempt: true)
        material = create(:material, default_price: BigDecimal("80.00"))
        em = create(:estimate_material, estimate: estimate, material: material, quote_price: BigDecimal("80.00"))

        expect(em.cost_with_tax).to eq(BigDecimal("80.00"))
      end
    end

    context "when quote_price is zero" do
      it "sets cost_with_tax = 0" do
        estimate = create(:estimate, tax_rate: BigDecimal("0.08"), tax_exempt: false)
        material = create(:material, default_price: BigDecimal("0"))
        em = create(:estimate_material, estimate: estimate, material: material, quote_price: BigDecimal("0"))

        expect(em.cost_with_tax).to eq(BigDecimal("0"))
      end
    end
  end
end
