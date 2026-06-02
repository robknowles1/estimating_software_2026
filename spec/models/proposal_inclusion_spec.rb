require "rails_helper"

RSpec.describe ProposalInclusion, type: :model do
  subject(:inclusion) { build(:proposal_inclusion) }

  describe "associations" do
    it { is_expected.to belong_to(:proposal) }
  end

  describe "validations" do
    it { is_expected.to validate_presence_of(:room_name) }

    it "is valid with a room_name and no photo" do
      expect(inclusion).to be_valid
    end
  end

  describe "photo attachment validations" do
    let(:proposal) { create(:proposal) }

    # Marcel (via ActiveStorage identify:true) overrides the declared content_type using
    # magic-byte detection, falling back to filename extension when bytes are unrecognisable.
    # Tests rely on filename extensions (.jpg, .pdf, .jpg) to drive the stored content_type —
    # the declared content_type: argument is intentionally ignored by Marcel in all three cases.

    it "is valid with a JPEG photo under 8 MB" do
      record = build(:proposal_inclusion, proposal: proposal)
      record.photo.attach(
        io:           StringIO.new("fake jpeg data"),
        filename:     "photo.jpg",
        content_type: "image/jpeg"
      )
      expect(record).to be_valid
    end

    it "is invalid when the photo content type is not an image" do
      record = build(:proposal_inclusion, proposal: proposal)
      record.photo.attach(
        io:           StringIO.new("fake pdf data"),
        filename:     "document.pdf",
        content_type: "application/pdf"
      )
      expect(record).to be_invalid
      expect(record.errors[:photo]).not_to be_empty
    end

    it "is invalid when the photo exceeds 8 MB" do
      record = build(:proposal_inclusion, proposal: proposal)
      large_data = "x" * (8.megabytes + 1)
      record.photo.attach(
        io:           StringIO.new(large_data),
        filename:     "large.jpg",
        content_type: "image/jpeg"
      )
      expect(record).to be_invalid
      expect(record.errors[:photo]).not_to be_empty
    end
  end
end
