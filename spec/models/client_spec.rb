require "rails_helper"

RSpec.describe Client, type: :model do
  describe "validations" do
    it { is_expected.to validate_presence_of(:company_name) }
  end

  describe "associations" do
    it { is_expected.to have_many(:contacts).dependent(:destroy) }
    it { is_expected.to have_one(:primary_contact).class_name("Contact") }
  end

  describe "restrict deletion when estimates exist" do
    it "has estimates association configured with restrict_with_error" do
      reflection = Client.reflect_on_association(:estimates)
      expect(reflection).not_to be_nil
      expect(reflection.options[:dependent]).to eq(:restrict_with_error)
    end

    # Full deletion guard is tested in request spec via controller stub.
    # A full AR-level test requires the Estimate model (built in Phase 3).
  end

  describe ".alphabetical scope" do
    it "returns clients sorted by company_name" do
      client_c = create(:client, company_name: "Zebrawood Co")
      client_a = create(:client, company_name: "Acme Corp")
      client_b = create(:client, company_name: "Maple Millwork")

      expect(Client.alphabetical.map(&:company_name)).to eq([
        "Acme Corp", "Maple Millwork", "Zebrawood Co"
      ])
    end
  end
end
