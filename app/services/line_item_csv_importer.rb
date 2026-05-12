require "csv"

class LineItemCsvImporter
  Result = Data.define(:line_items_created, :error)

  def initialize(estimate, file)
    @estimate = estimate
    @file     = file
  end

  def call
    groups = parse_csv
    persist(groups)
  rescue CSV::MalformedCSVError, ArgumentError => e
    Result.new(line_items_created: 0, error: e.message)
  rescue ActiveRecord::RecordInvalid => e
    Result.new(line_items_created: 0, error: e.message)
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
    created_count = 0

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
        line_item.save!

        created_count += 1
      end
    end

    Result.new(line_items_created: created_count, error: nil)
  rescue ActiveRecord::RecordInvalid => e
    raise e
  end
end
