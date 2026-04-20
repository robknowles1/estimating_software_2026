require "rails_helper"

RSpec.describe MaterialSet, type: :model do
  describe "validations" do
    it { is_expected.to validate_presence_of(:name) }
  end

  describe "associations" do
    it { is_expected.to have_many(:material_set_items).dependent(:destroy) }
    it { is_expected.to have_many(:materials).through(:material_set_items) }
  end

  describe "dependent: :destroy on material_set_items" do
    it "destroys associated material_set_items when the set is destroyed" do
      set = create(:material_set)
      create(:material_set_item, material_set: set)
      create(:material_set_item, material_set: set)

      expect { set.destroy }.to change(MaterialSetItem, :count).by(-2)
    end
  end
end
