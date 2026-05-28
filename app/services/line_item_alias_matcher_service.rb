class LineItemAliasMatcherService
  Result = Data.define(:matched, :unmatched, :ambiguous) do
    # Returns the appropriate i18n flash string.
    # +scope+ should be the i18n scope string, e.g. "line_items.apply_aliases"
    def flash_notice(scope)
      total = matched + unmatched
      if ambiguous > 0 && unmatched > 0
        I18n.t("#{scope}.notice_with_unmatched_and_ambiguous",
               total: total, unmatched: unmatched, ambiguous: ambiguous)
      elsif ambiguous > 0
        I18n.t("#{scope}.notice_with_ambiguity", total: total, ambiguous: ambiguous)
      elsif unmatched > 0
        I18n.t("#{scope}.notice_with_unmatched", total: total, unmatched: unmatched)
      elsif matched > 0
        I18n.t("#{scope}.notice_all_matched", total: total)
      else
        I18n.t("#{scope}.notice", matched: matched, unmatched: unmatched)
      end
    end
  end

  PRIMARY_SLOTS = %i[exterior_material_id interior_material_id interior2_material_id back_material_id].freeze

  def initialize(estimate)
    @estimate = estimate
    # Load all estimate_materials with a non-blank short_code, sorted longest first
    @code_entries = estimate.estimate_materials
      .where.not(short_code: [ nil, "" ])
      .sort_by { |em| -em.short_code.length }
  end

  # Match a single line item against the price book short codes.
  # Assigns the four primary material slots on the line item (does not save).
  # Returns the matched EstimateMaterial or nil.
  def match(line_item)
    return nil if @code_entries.empty?

    desc = line_item.description.to_s.downcase

    matched_em = @code_entries.find { |em| desc.include?(em.short_code.downcase) }
    return nil unless matched_em

    PRIMARY_SLOTS.each { |slot| line_item.public_send(:"#{slot}=", matched_em.id) }
    matched_em
  end

  # Returns true if, after the longest match has been selected, the description
  # still contains at least one other short code as a substring.
  def ambiguous?(line_item, matched_em)
    return false unless matched_em

    desc = line_item.description.to_s.downcase
    @code_entries.any? do |em|
      em != matched_em && desc.include?(em.short_code.downcase)
    end
  end

  # Apply short code matching to all line items on the estimate.
  # Saves matched line items inside a single transaction.
  # Returns a Result struct with matched, unmatched, and ambiguous counts.
  def apply_to_all_line_items
    matched_count   = 0
    unmatched_count = 0
    ambiguous_count = 0

    ActiveRecord::Base.transaction do
      @estimate.line_items.each do |line_item|
        matched_em = match(line_item)

        if matched_em
          ambiguous_count += 1 if ambiguous?(line_item, matched_em)
          line_item.save!
          matched_count += 1
        else
          unmatched_count += 1
        end
      end
    end

    Result.new(matched: matched_count, unmatched: unmatched_count, ambiguous: ambiguous_count)
  end
end
