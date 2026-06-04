require "rails_helper"

RSpec.describe ProposalInclusion, type: :model do
  subject(:inclusion) { build(:proposal_inclusion) }

  describe "associations" do
    it { is_expected.to belong_to(:proposal) }
    it { is_expected.to have_many_attached(:photos) }
  end

  describe "validations" do
    it { is_expected.to validate_presence_of(:room_name) }

    it "is valid with a room_name and no photos" do
      expect(inclusion).to be_valid
    end
  end

  describe "photo attachment validations" do
    let(:proposal) { create(:proposal) }

    # Marcel (via ActiveStorage identify:true) overrides the declared content_type using
    # magic-byte detection, falling back to filename extension when bytes are unrecognisable.
    # Tests rely on filename extensions (.jpg, .png, .pdf, .webp) to drive the stored
    # content_type — the declared content_type: argument is intentionally ignored by Marcel.

    it "is valid with a JPEG photo" do
      record = build(:proposal_inclusion, proposal: proposal)
      record.photos.attach(
        io:           StringIO.new("fake jpeg data"),
        filename:     "photo.jpg",
        content_type: "image/jpeg"
      )
      expect(record).to be_valid
    end

    it "is valid with a PNG photo" do
      record = build(:proposal_inclusion, proposal: proposal)
      record.photos.attach(
        io:           StringIO.new("fake png data"),
        filename:     "photo.png",
        content_type: "image/png"
      )
      expect(record).to be_valid
    end

    it "is valid with multiple photos attached" do
      record = build(:proposal_inclusion, proposal: proposal)
      record.photos.attach(
        io:           StringIO.new("fake jpeg data"),
        filename:     "first.jpg",
        content_type: "image/jpeg"
      )
      record.photos.attach(
        io:           StringIO.new("fake png data"),
        filename:     "second.png",
        content_type: "image/png"
      )
      expect(record).to be_valid
      expect(record.photos.size).to eq(2)
    end

    it "is invalid when a photo content type is not an image" do
      record = build(:proposal_inclusion, proposal: proposal)
      record.photos.attach(
        io:           StringIO.new("fake pdf data"),
        filename:     "document.pdf",
        content_type: "application/pdf"
      )
      expect(record).to be_invalid
      expect(record.errors[:photos]).not_to be_empty
    end

    it "is invalid when a photo is a WebP image (Prawn cannot embed WebP)" do
      record = build(:proposal_inclusion, proposal: proposal)
      record.photos.attach(
        io:           StringIO.new("fake webp data"),
        filename:     "photo.webp",
        content_type: "image/webp"
      )
      expect(record).to be_invalid
      expect(record.errors[:photos]).not_to be_empty
    end

    it "is invalid when a photo is a GIF image" do
      record = build(:proposal_inclusion, proposal: proposal)
      record.photos.attach(
        io:           StringIO.new("fake gif data"),
        filename:     "photo.gif",
        content_type: "image/gif"
      )
      expect(record).to be_invalid
      expect(record.errors[:photos]).not_to be_empty
    end

    it "is invalid when any of several photos is not JPEG/PNG" do
      record = build(:proposal_inclusion, proposal: proposal)
      record.photos.attach(
        io:           StringIO.new("fake jpeg data"),
        filename:     "ok.jpg",
        content_type: "image/jpeg"
      )
      record.photos.attach(
        io:           StringIO.new("fake webp data"),
        filename:     "bad.webp",
        content_type: "image/webp"
      )
      expect(record).to be_invalid
      expect(record.errors[:photos]).not_to be_empty
    end
  end
end
