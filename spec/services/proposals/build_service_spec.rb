require "rails_helper"

RSpec.describe Proposals::BuildService do
  # profit/PM percents are set so the burden multiplier is non-trivial (1.21),
  # tax is zero to keep cost_with_tax == quote_price for easy assertions.
  let(:estimate) do
    create(:estimate,
           profit_overhead_percent: BigDecimal("10"),
           pm_supervision_percent:  BigDecimal("10"),
           tax_rate:                BigDecimal("0"),
           tax_exempt:              true,
           installer_crew_size:     1)
  end

  before do
    %w[detail mill assembly customs finish install].each do |cat|
      create(:labor_rate, labor_category: cat, hourly_rate: BigDecimal("0"))
    end
  end

  subject(:service) { described_class.new(estimate: estimate) }

  describe "#call defaults" do
    it "creates exactly one Proposal" do
      expect { service.call }.to change(Proposal, :count).by(1)
    end

    it "creates a proposal in commercial mode, draft status, opening step" do
      proposal = service.call
      expect(proposal).to be_commercial
      expect(proposal).to be_draft
      expect(proposal.current_step).to eq("opening")
    end

    it "sets job_name from the estimate title" do
      expect(service.call.job_name).to eq(estimate.title)
    end

    it "sets total_amount to the estimate's burdened_total" do
      expected = EstimateTotalsCalculator.new(estimate).call.burdened_total
      expect(service.call.total_amount).to eq(expected)
    end
  end

  describe "standard clarifications (R11)" do
    it "seeds exactly two clarifications with the standard bodies in order" do
      proposal = service.call
      bodies = proposal.proposal_clarifications.order(:position).pluck(:body)
      expect(bodies).to eq(described_class::STANDARD_CLARIFICATIONS)
    end
  end

  describe "standard exclusions (R14)" do
    it "seeds exactly thirteen exclusions with the standard bodies in order" do
      proposal = service.call
      bodies = proposal.proposal_exclusions.order(:position).pluck(:body)
      expect(bodies.size).to eq(13)
      expect(bodies).to eq(described_class::STANDARD_EXCLUSIONS)
    end
  end

  describe "alternates (R12)" do
    let!(:material) { create(:material, default_price: BigDecimal("100.00")) }
    let!(:em) do
      create(:estimate_material, estimate: estimate, material: material, quote_price: BigDecimal("100.00"))
    end

    it "creates one ProposalAlternate per detected alternate line item" do
      alt = create(:line_item, estimate: estimate, description: "ALT-1 Painted Finish",
                               exterior_material_id: em.id, exterior_qty: BigDecimal("1"),
                               quantity: BigDecimal("1"))
      create(:line_item, estimate: estimate, description: "Base Cabinet")

      proposal = service.call

      expect(proposal.proposal_alternates.count).to eq(1)
      alternate = proposal.proposal_alternates.first
      expect(alternate.description).to eq("ALT-1 Painted Finish")
      expect(alternate.line_item_id).to eq(alt.id)
    end

    it "sets display_cost to non_burdened_total * burden_multiplier (gross/burdened)" do
      alt = create(:line_item, estimate: estimate, description: "Alternate upgrade",
                               exterior_material_id: em.id, exterior_qty: BigDecimal("1"),
                               quantity: BigDecimal("1"))

      totals = EstimateTotalsCalculator.new(estimate).call
      expected = (totals.line_item_results[alt.id][:non_burdened_total] * totals.burden_multiplier).round(2)

      # For this setup: one $100 material, all labor rates $0, tax exempt, so
      # non_burdened_total == 100.00. With 10% profit/overhead and 10% PM the
      # burden multiplier is 1.10 * 1.10 == 1.21, so display_cost == $121.00.
      # Pin the literal value too, so this fails if the multiplier degrades to 1.0.
      expect(expected).to eq(BigDecimal("121.00"))

      proposal = service.call
      expect(proposal.proposal_alternates.first.display_cost).to eq(expected)
      expect(proposal.proposal_alternates.first.display_cost).to eq(BigDecimal("121.00"))
    end

    it "creates no ProposalAlternate records when there are no alternate line items" do
      create(:line_item, estimate: estimate, description: "Base Cabinet")
      expect(service.call.proposal_alternates.count).to eq(0)
    end

    it "raises and rolls back when an alternate is missing from line_item_results" do
      create(:line_item, estimate: estimate, description: "Alternate upgrade",
                         exterior_material_id: em.id, exterior_qty: BigDecimal("1"),
                         quantity: BigDecimal("1"))

      # Stub the calculator so its result omits the alternate from
      # line_item_results, simulating an internal inconsistency. The Data shape
      # mirrors EstimateTotalsCalculator::Result.
      result = EstimateTotalsCalculator::Result.new(
        line_item_results:        {},
        grand_non_burdened_total: BigDecimal("0"),
        burden_multiplier:        BigDecimal("1.21"),
        job_level_costs:          {},
        burdened_total:           BigDecimal("0"),
        cogs_breakdown:           {},
        labor_hours_summary:      {},
        man_days_install:         BigDecimal("0")
      )
      calculator = instance_double(EstimateTotalsCalculator, call: result)
      allow(EstimateTotalsCalculator).to receive(:new).and_return(calculator)

      expect { service.call }.to raise_error(KeyError)
      expect(Proposal.count).to eq(0)
      expect(ProposalAlternate.count).to eq(0)
    end
  end

  describe "inclusions (R8)" do
    it "creates one inclusion per distinct non-blank room" do
      create(:line_item, estimate: estimate, description: "A", room: "Kitchen")
      create(:line_item, estimate: estimate, description: "B", room: "Kitchen")
      create(:line_item, estimate: estimate, description: "C", room: "Bathroom")

      rooms = service.call.proposal_inclusions.pluck(:room_name)
      expect(rooms).to match_array(%w[Kitchen Bathroom])
    end

    it "ignores blank-string and whitespace-only rooms" do
      create(:line_item, estimate: estimate, description: "A", room: "")
      create(:line_item, estimate: estimate, description: "B", room: nil)
      create(:line_item, estimate: estimate, description: "C", room: "   ")

      expect(service.call.proposal_inclusions.count).to eq(0)
    end

    it "strips surrounding whitespace and dedupes on the stripped value" do
      create(:line_item, estimate: estimate, description: "A", room: " Kitchen ")
      create(:line_item, estimate: estimate, description: "B", room: "Kitchen")

      rooms = service.call.proposal_inclusions.pluck(:room_name)
      expect(rooms).to eq(%w[Kitchen])
    end

    it "creates no inclusions when no line items have rooms" do
      create(:line_item, estimate: estimate, description: "A")
      expect(service.call.proposal_inclusions.count).to eq(0)
    end
  end

  describe "transaction safety" do
    it "rolls back and persists nothing when the proposal is invalid" do
      create(:proposal, estimate: estimate) # makes estimate_id non-unique

      expect { service.call }.to raise_error(ActiveRecord::RecordInvalid)
      expect(Proposal.where(estimate_id: estimate.id).count).to eq(1)
      expect(ProposalClarification.count).to eq(0)
      expect(ProposalExclusion.count).to eq(0)
      expect(ProposalAlternate.count).to eq(0)
      expect(ProposalInclusion.count).to eq(0)
    end
  end
end
