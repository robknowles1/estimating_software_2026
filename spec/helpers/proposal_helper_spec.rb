require "rails_helper"

RSpec.describe ProposalHelper, type: :helper do
  describe "#amount_in_words" do
    it "converts a whole-dollar amount to English words (R18)" do
      expect(helper.amount_in_words(123_000.00)).to eq("One Hundred Twenty-Three Thousand Dollars")
    end

    it "renders cents as an NN/100 fraction" do
      expect(helper.amount_in_words(1_000.50)).to eq("One Thousand Dollars and 50/100")
    end

    it "renders zero as 'Zero Dollars'" do
      expect(helper.amount_in_words(0.00)).to eq("Zero Dollars")
    end

    it "treats nil as zero" do
      expect(helper.amount_in_words(nil)).to eq("Zero Dollars")
    end

    it "omits the cents fraction when cents are zero" do
      expect(helper.amount_in_words(2_500.00)).to eq("Two Thousand Five Hundred Dollars")
    end

    # Rounding-edge: a value like 1.999 must round to 2.00 (cents never == 100)
    # rather than producing a phantom "100/100" fraction.
    it "rounds a sub-cent input up without producing 100 cents" do
      expect(helper.amount_in_words(1.999)).to eq("Two Dollars")
    end
  end
end
