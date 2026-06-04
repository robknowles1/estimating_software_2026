require "rails_helper"

RSpec.describe ProposalClarification, type: :model do
  subject(:clarification) { build(:proposal_clarification) }

  describe "associations" do
    it { is_expected.to belong_to(:proposal) }
  end

  describe "validations" do
    it { is_expected.to validate_presence_of(:body) }

    it "is valid with required attributes" do
      expect(clarification).to be_valid
    end
  end
end
