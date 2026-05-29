require "csv"

class LineItemCsvImporter
  Result = Data.define(:line_items_created, :matched_count, :unmatched_count, :ambiguous_count, :error) do
    # Returns the appropriate i18n key and interpolation variables for a flash notice.
    # +scope+ should be the i18n scope string, e.g. "line_items.import"
    def flash_notice(scope)
      imported = line_items_created
      if ambiguous_count > 0 && unmatched_count > 0
        I18n.t("#{scope}.notice_with_unmatched_and_ambiguous",
               imported: imported, unmatched: unmatched_count, ambiguous: ambiguous_count)
      elsif ambiguous_count > 0
        I18n.t("#{scope}.notice_with_ambiguity", imported: imported, ambiguous: ambiguous_count)
      elsif unmatched_count > 0
        I18n.t("#{scope}.notice_with_unmatched", imported: imported, unmatched: unmatched_count)
      elsif matched_count > 0
        I18n.t("#{scope}.notice_all_matched", imported: imported)
      else
        I18n.t("#{scope}.notice", count: imported)
      end
    end
  end

  def initialize(estimate, file)
    @estimate = estimate
    @file     = file
  end

  def call
    groups = parse_csv
    persist(groups)
  rescue CSV::MalformedCSVError, ArgumentError => e
    Result.new(line_items_created: 0, matched_count: 0, unmatched_count: 0, ambiguous_count: 0, error: e.message)
  rescue ActiveRecord::RecordInvalid => e
    Result.new(line_items_created: 0, matched_count: 0, unmatched_count: 0, ambiguous_count: 0, error: e.message)
  end

  private

  def parse_csv
    content = @file.read
    rows    = CSV.parse(content, liberal_parsing: true)

    groups        = []
    current_group = nil

    rows.each do |row|
      next if skip_row?(row)

      category       = row[0].to_s.strip
      product_number = row[4].to_s.strip
      name           = row[5].to_s.strip
      total_marker   = row[7].to_s.strip
      qty_raw        = row[8].to_s.strip
      unit           = row[9].to_s.strip

      if total_marker == "Total"
        # Override quantity on the current group with the Total row's qty
        if current_group
          current_group[:qty] = qty_raw.to_d
        end
      else
        # Non-Total row — start a new group when the product number changes
        if current_group.nil? || product_number != current_group[:product_number]
          groups << current_group if current_group
          current_group = {
            product_number: product_number,
            name:           name,
            category:       category,
            unit:           unit,
            qty:            qty_raw.to_d
          }
        end
      end
    end

    groups << current_group if current_group

    # Validate quantities
    if groups.empty?
      raise ArgumentError, "No valid product rows found in the CSV. Ensure the file matches the expected format."
    end

    groups.each do |group|
      if group[:qty] <= 0
        raise ArgumentError, "Product \"#{group[:name]}\" has a quantity of #{group[:qty]}, which must be greater than 0."
      end
    end

    groups
  end

  def skip_row?(row)
    return false if row[7].to_s.strip == "Total"

    category_cell = row[0].to_s.strip
    product_num   = row[4].to_s.strip

    return true if category_cell.start_with?("z")
    return true if product_num.blank? || product_num == "0"

    false
  end

  def persist(groups)
    created_count   = 0
    matched_count   = 0
    unmatched_count = 0
    ambiguous_count = 0

    matcher = LineItemAliasMatcherService.new(@estimate)

    ActiveRecord::Base.transaction do
      groups.each do |group|
        product = Product
          .where("lower(name) = ?", group[:name].downcase)
          .first_or_initialize

        if product.new_record?
          product.name     = group[:name]
          product.category = group[:category]
          product.unit     = group[:unit]
          product.save!
        end

        line_item = @estimate.line_items.new
        product.apply_to(line_item)
        line_item.description = product.name
        line_item.quantity    = group[:qty]
        line_item.product_id  = product.id

        # Step 1: alias matching (SPEC-022) — match short codes in the description
        matched_em = matcher.match(line_item)
        if matched_em
          ambiguous_count += 1 if matcher.ambiguous?(line_item, matched_em)
          matched_count += 1
        else
          unmatched_count += 1
        end

        # Step 2: product slot resolver (SPEC-029) — slot codes may override alias matches
        ProductSlotResolver.new(product, @estimate).call(line_item)

        line_item.save!
        created_count += 1
      end
    end

    Result.new(
      line_items_created: created_count,
      matched_count:      matched_count,
      unmatched_count:    unmatched_count,
      ambiguous_count:    ambiguous_count,
      error:              nil
    )
  rescue ActiveRecord::RecordInvalid => e
    raise e
  end
end
