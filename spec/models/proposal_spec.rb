require "rails_helper"

RSpec.describe Proposal, type: :model do
  subject(:proposal) { build(:proposal) }

  describe "associations" do
    it { is_expected.to belong_to(:estimate) }
    it { is_expected.to belong_to(:contact).optional }
    it { is_expected.to have_many(:proposal_inclusions).dependent(:destroy) }
    it { is_expected.to have_many(:proposal_clarifications).dependent(:destroy) }
    it { is_expected.to have_many(:proposal_exclusions).dependent(:destroy) }
    it { is_expected.to have_many(:proposal_alternates).dependent(:destroy) }
    it { is_expected.to have_many(:proposal_specifications).dependent(:destroy) }
  end

  describe "validations" do
    it { is_expected.to validate_presence_of(:mode) }
    it { is_expected.to validate_presence_of(:status) }
    it { is_expected.to validate_presence_of(:current_step) }

    it "is valid with all required attributes" do
      expect(proposal).to be_valid
    end

    it "is invalid without an estimate" do
      proposal.estimate = nil
      expect(proposal).to be_invalid
      expect(proposal.errors[:estimate]).not_to be_empty
    end

    it "enforces uniqueness of estimate_id" do
      existing = create(:proposal)
      duplicate = build(:proposal, estimate: existing.estimate)
      expect(duplicate).to be_invalid
      expect(duplicate.errors[:estimate_id]).not_to be_empty
    end
  end

  describe "enum :mode" do
    it "accepts commercial" do
      proposal.mode = "commercial"
      expect(proposal).to be_valid
      expect(proposal.commercial?).to be true
    end

    it "accepts residential" do
      proposal.mode = "residential"
      expect(proposal).to be_valid
      expect(proposal.residential?).to be true
    end
  end

  describe "enum :status" do
    it "accepts draft" do
      proposal.status = "draft"
      expect(proposal).to be_valid
      expect(proposal.draft?).to be true
    end

    it "accepts sent" do
      proposal.status = "sent"
      expect(proposal).to be_valid
      expect(proposal.sent?).to be true
    end
  end

  describe "ALTERNATE_PREFIXES constant" do
    it "exists on the model" do
      expect(described_class).to be_const_defined(:ALTERNATE_PREFIXES)
    end

    it "matches ALT prefix (case-insensitive)" do
      expect("ALT-1 Painted Finish").to match(described_class::ALTERNATE_PREFIXES)
      expect("alt-1 painted finish").to match(described_class::ALTERNATE_PREFIXES)
    end

    it "matches Alternate prefix" do
      expect("Alternate 1 - Painted Finish").to match(described_class::ALTERNATE_PREFIXES)
    end

    it "matches Alt. prefix" do
      expect("Alt. 1 Painted Finish").to match(described_class::ALTERNATE_PREFIXES)
    end

    it "does not match ALT embedded mid-string" do
      expect("Base Cabinet ALT Finish").not_to match(described_class::ALTERNATE_PREFIXES)
    end
  end
end
