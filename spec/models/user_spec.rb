require 'rails_helper'

RSpec.describe User, type: :model do
  subject(:user) { build(:user) }

  # Shoulda-matchers validations
  it { is_expected.to validate_presence_of(:name) }
  it { is_expected.to validate_presence_of(:email) }
  it { is_expected.to validate_uniqueness_of(:email).case_insensitive }
  it { is_expected.to have_secure_password }

  describe "valid record" do
    it "saves with correct fields" do
      expect(user.save).to be true
    end
  end

  describe "email format validation" do
    it "rejects an invalid email" do
      user.email = "not-an-email"
      expect(user).not_to be_valid
      expect(user.errors[:email]).to be_present
    end

    it "accepts a valid email" do
      user.email = "valid@example.com"
      expect(user).to be_valid
    end
  end

  describe "authentication" do
    let!(:persisted_user) { create(:user) }

    it "returns the user when given the correct password" do
      expect(persisted_user.authenticate("password123")).to eq(persisted_user)
    end

    it "returns false when given an incorrect password" do
      expect(persisted_user.authenticate("wrong")).to be false
    end
  end

  describe "email uniqueness (case-insensitive)" do
    let!(:existing) { create(:user, email: "Alice@Example.com") }

    it "rejects a duplicate email in a different case" do
      duplicate = build(:user, email: "alice@example.com")
      expect(duplicate).not_to be_valid
      expect(duplicate.errors[:email]).to be_present
    end
  end

  describe "presence validations" do
    it "rejects blank name" do
      user.name = ""
      expect(user).not_to be_valid
      expect(user.errors[:name]).to be_present
    end

    it "rejects blank email" do
      user.email = ""
      expect(user).not_to be_valid
      expect(user.errors[:email]).to be_present
    end
  end
end
