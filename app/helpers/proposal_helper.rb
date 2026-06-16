require "humanize"

module ProposalHelper
  def amount_in_words(amount)
    value = (amount || 0).to_d.round(2)
    dollars = value.to_i
    cents = ((value - dollars) * 100).round.to_i

    words = "#{title_case_words(dollars)} Dollars"
    words += " and #{cents.to_s.rjust(2, '0')}/100" if cents.positive?
    words
  end

  private

  def title_case_words(number)
    raw = number.humanize.gsub(/\band\b/, "").delete(",").squeeze(" ").strip
    raw.split(" ").map { |word| word.split("-").map(&:capitalize).join("-") }.join(" ")
  end
end
