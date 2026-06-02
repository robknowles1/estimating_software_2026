require "rails_helper"

RSpec.describe ProposalExclusion, type: :model do
  subject(:exclusion) { build(:proposal_exclusion) }

  describe "associations" do
    it { is_expected.to belong_to(:proposal) }
  end

  describe "validations" do
    it { is_expected.to validate_presence_of(:body) }

    it "is valid with required attributes" do
      expect(exclusion).to be_valid
    end
  end
end
