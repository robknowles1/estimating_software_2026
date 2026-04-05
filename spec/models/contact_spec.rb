require "rails_helper"

RSpec.describe Contact, type: :model do
  describe "validations" do
    it { is_expected.to validate_presence_of(:first_name) }
    it { is_expected.to validate_presence_of(:last_name) }
  end

  describe "associations" do
    it { is_expected.to belong_to(:client) }
  end

  describe "primary flag management" do
    it "clears is_primary on sibling contacts when a new contact is set to primary" do
      client  = create(:client)
      first   = create(:contact, client: client, is_primary: true)
      second  = create(:contact, client: client, is_primary: false)

      second.update!(is_primary: true)

      expect(second.reload.is_primary).to be true
      expect(first.reload.is_primary).to be false
    end

    it "does not affect contacts on other clients" do
      client_a = create(:client)
      client_b = create(:client)
      contact_a = create(:contact, client: client_a, is_primary: true)
      contact_b = create(:contact, client: client_b, is_primary: false)

      contact_b.update!(is_primary: true)

      expect(contact_a.reload.is_primary).to be true
    end

    it "allows a non-primary contact to be saved without clearing siblings" do
      client   = create(:client)
      primary  = create(:contact, client: client, is_primary: true)
      sibling  = create(:contact, client: client, is_primary: false)

      sibling.update!(first_name: "Updated")

      expect(primary.reload.is_primary).to be true
    end
  end

  describe "database-level partial unique index on is_primary" do
    it "prevents two primary contacts for the same client at the database level" do
      client = create(:client)
      create(:contact, client: client, is_primary: true)

      duplicate = build(:contact, client: client, is_primary: true)
      # Bypass the before_save callback to test the DB constraint directly
      duplicate.instance_variable_set(:@skip_callback, true)
      allow(duplicate).to receive(:clear_sibling_primary_flags)

      expect {
        duplicate.save!(validate: false)
      }.to raise_error(ActiveRecord::RecordNotUnique)
    end
  end
end
