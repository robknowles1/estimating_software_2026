require "rails_helper"

RSpec.describe EstimateMaterial, type: :model do
  describe "associations" do
    it { is_expected.to belong_to(:estimate) }
    it { is_expected.to belong_to(:material) }
  end

  describe "validations" do
    it { is_expected.to validate_numericality_of(:quote_price).is_greater_than_or_equal_to(0) }

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
