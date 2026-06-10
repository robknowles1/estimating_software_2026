require "rails_helper"

RSpec.describe ClientNote, type: :model do
  describe "validations" do
    it "is valid with a body" do
      note = build(:client_note, body: "Called Blake re: bid deadline")
      expect(note).to be_valid
    end

    it "is invalid with a blank body" do
      note = build(:client_note, body: "")
      expect(note).not_to be_valid
      expect(note.errors[:body]).to be_present
    end

    it "is invalid with a whitespace-only body and is not saved" do
      note = build(:client_note, body: "   ")
      expect(note).not_to be_valid
      expect(note.errors[:body]).to be_present
      expect { note.save }.not_to change(ClientNote, :count)
    end

    it { is_expected.to validate_presence_of(:body) }
  end

  describe "associations" do
    it { is_expected.to belong_to(:client) }
  end

  describe "cascade delete" do
    it "destroys its notes when the client is destroyed" do
      client = create(:client)
      create(:client_note, client: client)
      create(:client_note, client: client)

      expect {
        client.destroy
      }.to change(ClientNote, :count).by(-2)
    end
  end

  describe "default association order" do
    it "returns notes newest-first" do
      client = create(:client)
      older  = create(:client_note, client: client, created_at: 2.days.ago)
      newer  = create(:client_note, client: client, created_at: 1.hour.ago)

      expect(client.client_notes.to_a).to eq([ newer, older ])
    end
  end
end
