require "rails_helper"

RSpec.describe Proposals::EmailDeliveryService do
  let(:client)   { create(:client) }
  let(:estimate) { create(:estimate, client: client) }
  let(:contact)  { create(:contact, client: client, email: "dana@example.com") }
  let(:proposal) { Proposals::BuildService.new(estimate: estimate).call }

  before { ActionMailer::Base.deliveries.clear }

  describe "#call with a valid recipient" do
    subject(:result) do
      described_class.new(proposal: proposal, recipient_email: "client@example.com").call
    end

    it "delivers exactly one email" do
      expect { result }.to change { ActionMailer::Base.deliveries.size }.by(1)
    end

    it "returns a success result" do
      expect(result.success).to be(true)
      expect(result.error).to be_nil
    end
  end

  describe "#call with an invalid recipient" do
    [ "", "   ", nil, "not-an-email", "a@b.com\nBcc: x@y.com", "a@b.com\rBcc: x@y.com", "a@b.com;c@d.com", ";" ].each do |bad|
      it "raises ArgumentError and sends nothing for #{bad.inspect}" do
        service = described_class.new(proposal: proposal, recipient_email: bad)

        expect { service.call }.to raise_error(ArgumentError)
        expect(ActionMailer::Base.deliveries).to be_empty
      end
    end

    it "raises before any PDF render work" do
      expect(Proposals::PdfRenderService).not_to receive(:new)

      expect {
        described_class.new(proposal: proposal, recipient_email: "").call
      }.to raise_error(ArgumentError)
    end
  end

  describe "#call when delivery fails" do
    subject(:result) do
      described_class.new(proposal: proposal, recipient_email: "client@example.com").call
    end

    before do
      # Stub the PDF render so the failure is triggered deterministically by the
      # delivery step, not by any real PDF work.
      allow_any_instance_of(Proposals::PdfRenderService)
        .to receive(:call).and_return("%PDF-stub")

      mailer = double
      allow(ProposalMailer).to receive(:proposal_email).and_return(mailer)
      allow(mailer).to receive(:deliver_now).and_raise(StandardError, "smtp down")
    end

    it "returns a failure result with an error message" do
      expect(result.success).to be(false)
      expect(result.error).to be_present
    end

    it "sends no email" do
      result
      expect(ActionMailer::Base.deliveries).to be_empty
    end
  end
end
