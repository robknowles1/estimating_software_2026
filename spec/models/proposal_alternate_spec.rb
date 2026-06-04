require "rails_helper"

RSpec.describe ProposalAlternate, type: :model do
  subject(:alternate) { build(:proposal_alternate) }

  describe "associations" do
    it { is_expected.to belong_to(:proposal) }
    it { is_expected.to belong_to(:line_item).optional }
  end

  describe "validations" do
    it { is_expected.to validate_presence_of(:description) }
    it { is_expected.to validate_presence_of(:display_cost) }

    it "is valid with required attributes" do
      expect(alternate).to be_valid
    end
  end
end
