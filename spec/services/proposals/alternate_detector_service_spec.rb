require "rails_helper"

RSpec.describe Proposals::AlternateDetectorService do
  let(:estimate) { create(:estimate) }

  subject(:service) { described_class.new(estimate: estimate) }

  def line_item_with(description, position: 1)
    create(:line_item, estimate: estimate, description: description, position: position)
  end

  describe "#call" do
    it "returns line items whose description begins with ALT (case-insensitive)" do
      match = line_item_with("ALT-1 Painted Finish")
      expect(service.call).to eq([ match ])
    end

    it "returns line items whose description begins with a lowercase alt prefix" do
      match = line_item_with("alt upgraded hardware")
      expect(service.call).to eq([ match ])
    end

    it "returns line items whose description begins with Alt." do
      match = line_item_with("Alt. quartz countertop")
      expect(service.call).to eq([ match ])
    end

    it "returns line items whose description begins with Alternate" do
      match = line_item_with("Alternate stainless backsplash")
      expect(service.call).to eq([ match ])
    end

    it "does not return line items where the prefix appears mid-string" do
      line_item_with("Base Cabinet ALT Finish")
      expect(service.call).to eq([])
    end

    it "returns an empty array when no line items match" do
      line_item_with("Base Cabinet")
      line_item_with("Upper Cabinet")
      expect(service.call).to eq([])
    end

    it "returns matches in stable position order" do
      second = line_item_with("Alt. second option", position: 2)
      first  = line_item_with("ALT first option", position: 1)
      line_item_with("Regular cabinet", position: 3)

      expect(service.call).to eq([ first, second ])
    end
  end
end
