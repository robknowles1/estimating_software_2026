require "rails_helper"

RSpec.describe ProposalSpecification, type: :model do
  subject(:spec_record) { build(:proposal_specification) }

  describe "associations" do
    it { is_expected.to belong_to(:proposal) }
  end

  describe "validations" do
    it { is_expected.to validate_presence_of(:spec_number) }
    it { is_expected.to validate_presence_of(:spec_title) }

    it "is valid with required attributes" do
      expect(spec_record).to be_valid
    end
  end
end
