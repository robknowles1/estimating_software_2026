require "rails_helper"

RSpec.describe LineItem, type: :model do
  subject(:line_item) { build(:line_item) }

  describe "associations" do
    it { is_expected.to belong_to(:estimate) }
    it { is_expected.to belong_to(:exterior_material).optional }
    it { is_expected.to belong_to(:interior_material).optional }
    it { is_expected.to belong_to(:interior2_material).optional }
    it { is_expected.to belong_to(:back_material).optional }
    it { is_expected.to belong_to(:banding_material).optional }
    it { is_expected.to belong_to(:drawers_material).optional }
    it { is_expected.to belong_to(:pulls_material).optional }
    it { is_expected.to belong_to(:hinges_material).optional }
    it { is_expected.to belong_to(:slides_material).optional }
  end

  describe "validations" do
    it { is_expected.to validate_presence_of(:description) }
    it { is_expected.to validate_presence_of(:unit) }
    it { is_expected.to validate_numericality_of(:quantity).is_greater_than(0) }
  end

  describe "acts_as_list" do
    it "appends new line items at the bottom of the estimate's list" do
      estimate = create(:estimate, :skip_material_seeding)
      first  = create(:line_item, estimate: estimate)
      second = create(:line_item, estimate: estimate)
      expect(first.position).to be < second.position
    end
  end
end
