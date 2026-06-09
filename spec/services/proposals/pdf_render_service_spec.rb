require "rails_helper"
require "pdf-reader"

RSpec.describe Proposals::PdfRenderService do
  subject(:pdf) { described_class.new(proposal: proposal).call }

  # Extracts all text from the rendered PDF binary (AT14).
  def pdf_text(binary)
    PDF::Reader.new(StringIO.new(binary)).pages.map(&:text).join("\n")
  end

  describe "binary output" do
    let(:proposal) { create(:proposal) }

    it "returns a non-empty string" do
      expect(pdf).to be_a(String)
      expect(pdf).not_to be_empty
    end

    it "begins with the PDF header" do
      expect(pdf).to start_with("%PDF")
    end
  end

  describe "commercial mode, fully populated" do
    let(:client)  { create(:client) }
    let(:contact) { create(:contact, client: client, first_name: "Dana", last_name: "Reed") }
    let(:estimate) { create(:estimate, client: client) }
    let(:proposal) do
      create(:proposal,
             estimate: estimate,
             contact: contact,
             mode: "commercial",
             job_name: "Acme HQ Millwork",
             plan_date: Date.new(2026, 3, 14),
             addendum_list: "1, 2",
             total_amount: BigDecimal("123000.00"),
             include_specifications: true)
    end

    before do
      create(:proposal_specification, proposal: proposal)
      inclusion = create(:proposal_inclusion, proposal: proposal, room_name: "Kitchen",
                                              bullet_points: "New uppers\nNew lowers")
      inclusion.photos.attach(
        io: File.open(Rails.root.join("spec/fixtures/files/sample_photo.jpg")),
        filename: "sample_photo.jpg",
        content_type: "image/jpeg"
      )
      create(:proposal_clarification, proposal: proposal, body: "Slab doors")
      create(:proposal_alternate, proposal: proposal, description: "ALT-1 Painted", display_cost: BigDecimal("500.00"))
      create(:proposal_exclusion, proposal: proposal, body: "Man doors")
    end

    it "does not raise" do
      expect { pdf }.not_to raise_error
    end

    # AT14 — content coverage via text extraction.
    it "contains the contact first name, job name, plan date, and total in numeric and word forms" do
      text = pdf_text(pdf)
      expect(text).to include("Dana")
      expect(text).to include("Acme HQ Millwork")
      expect(text).to include("March 14, 2026")
      expect(text).to include("$123,000.00")
      expect(text).to include("One Hundred Twenty-Three Thousand Dollars")
    end
  end

  describe "residential mode, fully populated" do
    let(:proposal) do
      create(:proposal,
             mode: "residential",
             job_name: "Smith Kitchen",
             total_amount: BigDecimal("48000.00"),
             payment_terms: "50% deposit, balance on completion")
    end

    before do
      create(:proposal_inclusion, proposal: proposal, room_name: "Kitchen", bullet_points: "New cabinets")
      create(:proposal_alternate, proposal: proposal, description: "ALT-1 Quartz", display_cost: BigDecimal("2000.00"))
    end

    it "does not raise" do
      expect { pdf }.not_to raise_error
    end

    it "includes the payment terms" do
      expect(pdf_text(pdf)).to include("50% deposit")
    end
  end

  describe "sparse proposals" do
    it "does not raise with no inclusions" do
      proposal = create(:proposal)
      expect { described_class.new(proposal: proposal).call }.not_to raise_error
    end

    it "does not raise with no clarifications" do
      proposal = create(:proposal)
      proposal.proposal_clarifications.destroy_all
      expect { described_class.new(proposal: proposal).call }.not_to raise_error
    end

    it "does not raise with no alternates" do
      proposal = create(:proposal)
      expect(proposal.proposal_alternates).to be_empty
      expect { described_class.new(proposal: proposal).call }.not_to raise_error
    end

    it "does not raise with a nil contact (salutation guarded)" do
      proposal = create(:proposal, contact: nil)
      expect { described_class.new(proposal: proposal).call }.not_to raise_error
    end
  end

  describe "photo embedding" do
    let(:proposal) { create(:proposal, mode: "commercial") }
    let(:inclusion) { create(:proposal_inclusion, proposal: proposal, room_name: "Kitchen") }

    # True when any page in the rendered PDF references an image XObject. Prawn
    # embeds a raster photo as a `/Subtype /Image` XObject, so its presence
    # proves the JPEG was actually embedded (not just the skip path).
    def embedded_image?(binary)
      PDF::Reader.new(StringIO.new(binary)).pages.any? do |page|
        page.xobjects.values.any? { |xobj| xobj.hash[:Subtype] == :Image }
      end
    end

    before do
      inclusion.photos.attach(
        io: File.open(Rails.root.join("spec/fixtures/files/sample_photo.jpg")),
        filename: "sample_photo.jpg",
        content_type: "image/jpeg"
      )
    end

    it "embeds the attached JPEG as an image XObject in the PDF (R9)" do
      expect { pdf }.not_to raise_error
      expect(pdf).to start_with("%PDF")
      expect(embedded_image?(pdf)).to be(true)
    end

    # Graceful-skip contract: when the :pdf variant cannot be processed for a
    # single photo, that image is skipped and the rest of the PDF still renders
    # without raising and without an embedded image XObject.
    it "skips an un-processable photo and still renders the rest of the PDF" do
      failing_variant = instance_double(ActiveStorage::Variant)
      allow(failing_variant).to receive(:processed).and_raise(Vips::Error, "boom")
      allow_any_instance_of(ActiveStorage::Attachment)
        .to receive(:variant).with(:pdf).and_return(failing_variant)

      result = nil
      expect { result = pdf }.not_to raise_error
      expect(result).to start_with("%PDF")
      expect(embedded_image?(result)).to be(false)
    end
  end
end
