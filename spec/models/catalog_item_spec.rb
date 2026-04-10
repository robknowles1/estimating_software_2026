require "rails_helper"

RSpec.describe CatalogItem, type: :model do
  describe "validations" do
    it { is_expected.to validate_presence_of(:description) }
  end

  describe "associations" do
    it { is_expected.to have_many(:line_items).dependent(:nullify) }
  end

  describe ".search" do
    let!(:crown) { create(:catalog_item, description: "Crown Moulding", category: "millwork") }
    let!(:door)  { create(:catalog_item, description: "Door Casing",    category: "millwork") }
    let!(:hinge) { create(:catalog_item, description: "Concealed Hinge", category: "hardware") }

    it "returns items matching a substring case-insensitively" do
      results = CatalogItem.search("crown")
      expect(results).to include(crown)
      expect(results).not_to include(door)
    end

    it "is case-insensitive" do
      results = CatalogItem.search("CROWN")
      expect(results).to include(crown)
    end

    it "matches partial substrings" do
      results = CatalogItem.search("cas")
      expect(results).to include(door)
    end

    it "returns at most 10 results" do
      11.times { |i| create(:catalog_item, description: "Trim Item #{i}") }
      results = CatalogItem.search("Trim")
      expect(results.size).to be <= 10
    end

    it "returns empty array when no matches" do
      results = CatalogItem.search("zzz_no_match")
      expect(results).to be_empty
    end

    it "treats % and _ in the query as literals, not LIKE wildcards" do
      wildcard_item = create(:catalog_item, description: "50% Off Special")
      underscore_item = create(:catalog_item, description: "Part_Number_123")

      # "%" as a literal — should only match the item with a literal % in the name
      percent_results = CatalogItem.search("50%")
      expect(percent_results).to include(wildcard_item)
      expect(percent_results).not_to include(crown)
      expect(percent_results).not_to include(door)

      # "_" as a literal — should only match the item with a literal _ in the name
      underscore_results = CatalogItem.search("Part_")
      expect(underscore_results).to include(underscore_item)
      expect(underscore_results).not_to include(crown)
    end
  end

  describe "dependent: :nullify on line_items" do
    let(:catalog_item) { create(:catalog_item) }
    let(:estimate_section) { create(:estimate_section) }
    let!(:line_item) { create(:line_item, estimate_section: estimate_section, catalog_item: catalog_item) }

    it "nullifies catalog_item_id on associated line items when catalog item is destroyed" do
      expect { catalog_item.destroy }.not_to change(LineItem, :count)
      expect(line_item.reload.catalog_item_id).to be_nil
    end
  end
end
