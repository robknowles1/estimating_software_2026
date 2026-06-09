require "humanize"

module ProposalHelper
  # Converts a numeric total to an English-words dollar amount for the proposal
  # PDF (R18). The dollar portion is produced with the `humanize` gem and
  # title-cased; cents are rendered as a "NN/100" fraction.
  #
  # Cents format (chosen): when the amount has a non-zero cents portion the
  # words read "<dollars> Dollars and NN/100" (e.g. "One Thousand Dollars and
  # 50/100"); when cents are zero they are omitted entirely ("<dollars>
  # Dollars"). This matches the legal-style phrasing used on Blake's existing
  # bid letters.
  #
  # The `humanize` gem inserts an " and" conjunction before a sub-100 remainder
  # (e.g. 123_000 => "one hundred and twenty-three thousand"). The proposal copy
  # omits that conjunction, so it is stripped before title-casing. Title-casing
  # capitalises each whitespace- and hyphen-delimited token so "twenty-three"
  # becomes "Twenty-Three".
  #
  # nil is treated as 0 ("Zero Dollars") so a proposal whose total was never set
  # never breaks PDF generation.
  def amount_in_words(amount)
    amount = amount || 0
    dollars = amount.to_i
    cents = ((amount.to_f - dollars).round(2) * 100).round

    words = "#{title_case_words(dollars)} Dollars"
    words += " and #{cents.to_s.rjust(2, '0')}/100" if cents.positive?
    words
  end

  private

  def title_case_words(number)
    # The humanize gem separates thousand-groups with a comma and inserts an
    # " and" conjunction before a sub-100 remainder (e.g. 123_000 =>
    # "one hundred and twenty-three thousand", 2_500 => "two thousand, five
    # hundred"). The proposal copy uses neither, so both are stripped before
    # title-casing.
    raw = number.humanize.gsub(/\band\b/, "").delete(",").squeeze(" ").strip
    raw.split(" ").map { |word| word.split("-").map(&:capitalize).join("-") }.join(" ")
  end
end
