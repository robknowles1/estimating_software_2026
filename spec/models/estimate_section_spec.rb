require "rails_helper"

RSpec.describe EstimateSection, type: :model do
  subject(:section) { build(:estimate_section) }

  describe "associations" do
    it { is_expected.to belong_to(:estimate) }
  end

  describe "validations" do
    it { is_expected.to validate_presence_of(:name) }
    it { is_expected.to validate_numericality_of(:default_markup_percent).is_greater_than_or_equal_to(0) }
    it { is_expected.to validate_numericality_of(:quantity).is_greater_than(0) }
  end

  describe "acts_as_list" do
    it "inserts at the bottom of the list on create" do
      estimate = create(:estimate)
      first_section = create(:estimate_section, estimate: estimate)
      second_section = create(:estimate_section, estimate: estimate)

      expect(first_section.position).to be < second_section.position
    end

    it "supports move_higher and move_lower" do
      estimate = create(:estimate)
      first_section = create(:estimate_section, estimate: estimate, name: "First")
      second_section = create(:estimate_section, estimate: estimate, name: "Second")

      original_first_pos = first_section.position
      original_second_pos = second_section.position

      second_section.move_higher
      second_section.reload
      first_section.reload

      expect(second_section.position).to be < original_second_pos
      expect(first_section.position).to be > original_first_pos
    end
  end
end
