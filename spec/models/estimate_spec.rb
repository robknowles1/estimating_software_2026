require "rails_helper"

RSpec.describe Estimate, type: :model do
  subject(:estimate) { build(:estimate) }

  describe "associations" do
    it { is_expected.to belong_to(:client) }
    it { is_expected.to belong_to(:created_by).class_name("User") }
    it { is_expected.to have_many(:line_items).dependent(:destroy) }
  end

  describe "validations" do
    it { is_expected.to validate_presence_of(:title) }
    it { is_expected.to validate_presence_of(:client_id) }
    it { is_expected.to validate_uniqueness_of(:estimate_number) }
    it { is_expected.to validate_numericality_of(:tax_rate).is_greater_than_or_equal_to(0) }
  end

  describe "estimate number generation" do
    it "generates an estimate number on create" do
      estimate = create(:estimate)
      expect(estimate.estimate_number).to match(/\AEST-\d{4}-\d{4}\z/)
    end

    it "follows the EST-YYYY-NNNN format with current year" do
      estimate = create(:estimate)
      year = Date.current.year
      expect(estimate.estimate_number).to start_with("EST-#{year}-")
    end

    it "zero-pads the sequence to four digits" do
      estimate = create(:estimate)
      seq = estimate.estimate_number.split("-").last
      expect(seq.length).to eq(4)
    end

    it "increments the sequence for subsequent estimates in the same year" do
      first  = create(:estimate)
      second = create(:estimate)

      first_seq  = first.estimate_number.split("-").last.to_i
      second_seq = second.estimate_number.split("-").last.to_i

      expect(second_seq).to eq(first_seq + 1)
    end

    it "does not overwrite an existing estimate_number" do
      estimate = create(:estimate, estimate_number: "EST-2026-9999")
      expect(estimate.estimate_number).to eq("EST-2026-9999")
    end
  end

  describe "status enum" do
    it "defaults to draft" do
      estimate = build(:estimate)
      expect(estimate.status).to eq("draft")
    end

    it "accepts all valid status values" do
      %w[draft sent approved lost archived].each do |s|
        estimate = create(:estimate, status: s)
        expect(estimate).to be_valid
      end
    end

    it "rejects invalid status values" do
      expect { build(:estimate, status: "pending") }.to raise_error(ArgumentError)
    end
  end

  describe "#copy_tax_exempt_from_client (before_create)" do
    it "copies the client's tax_exempt value onto the estimate at creation" do
      client = create(:client, tax_exempt: true)
      estimate = create(:estimate, client: client)
      expect(estimate.tax_exempt).to be true
    end

    it "sets tax_exempt to false when client is not tax_exempt" do
      client = create(:client, tax_exempt: false)
      estimate = create(:estimate, client: client)
      expect(estimate.tax_exempt).to be false
    end

    it "does not re-copy tax_exempt from client on update" do
      client = create(:client, tax_exempt: false)
      estimate = create(:estimate, client: client)

      # Manually change the estimate's tax_exempt (simulates a per-job override)
      estimate.update!(tax_exempt: true)

      # Update client tax status — should NOT affect the existing estimate
      client.update!(tax_exempt: false)
      estimate.update!(title: "Updated Title")

      expect(estimate.reload.tax_exempt).to be true
    end
  end

  describe "scopes" do
    let!(:draft_estimate)    { create(:estimate, status: "draft") }
    let!(:sent_estimate)     { create(:estimate, status: "sent") }
    let!(:approved_estimate) { create(:estimate, status: "approved") }

    describe ".with_status" do
      it "filters by status when a value is provided" do
        results = Estimate.with_status("sent")
        expect(results).to include(sent_estimate)
        expect(results).not_to include(draft_estimate)
      end

      it "returns all records when status is blank" do
        results = Estimate.with_status("")
        expect(results).to include(draft_estimate, sent_estimate, approved_estimate)
      end
    end

    describe ".search" do
      let!(:client_a)    { create(:client, company_name: "Acme Corp") }
      let!(:estimate_a)  { create(:estimate, client: client_a, title: "Big Kitchen") }
      let!(:estimate_b)  { create(:estimate, title: "Bathroom Remodel") }

      it "filters by title" do
        results = Estimate.search("Kitchen")
        expect(results).to include(estimate_a)
        expect(results).not_to include(estimate_b)
      end

      it "filters by client company name" do
        results = Estimate.search("Acme")
        expect(results).to include(estimate_a)
        expect(results).not_to include(estimate_b)
      end

      it "returns all records when query is blank" do
        results = Estimate.search("")
        expect(results).to include(estimate_a, estimate_b)
      end

      it "is case-insensitive" do
        results = Estimate.search("kitchen")
        expect(results).to include(estimate_a)
      end
    end
  end
end
