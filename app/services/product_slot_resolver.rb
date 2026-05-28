# Resolves an estimate's price book short codes against a product's slot code
# hints, and assigns matched estimate_material IDs to a line item's FK columns.
#
# Usage:
#   ProductSlotResolver.new(product, estimate).call(line_item)
#
# Does not save. Caller is responsible for persisting the line item.
#
# locks_slot_code is intentionally excluded from SLOT_MAP — no locks_material_id
# column exists on line_items; locks resolves by role at calculator time.
class ProductSlotResolver
  SLOT_MAP = {
    exterior:  :exterior_slot_code,
    interior:  :interior_slot_code,
    interior2: :interior2_slot_code,
    back:      :back_slot_code,
    banding:   :banding_slot_code,
    drawers:   :drawers_slot_code,
    pulls:     :pulls_slot_code,
    hinges:    :hinges_slot_code,
    slides:    :slides_slot_code
  }.freeze

  def initialize(product, estimate)
    @product = product
    @code_index = estimate.estimate_materials
                          .where.not(short_code: [ nil, "" ])
                          .index_by { |em| em.short_code.downcase }
  end

  def call(line_item)
    return line_item if @code_index.empty?

    SLOT_MAP.each do |slot, code_attr|
      hint = @product.public_send(code_attr).to_s.strip.downcase
      next if hint.blank?

      matched = @code_index[hint]
      line_item.public_send(:"#{slot}_material_id=", matched&.id)
    end

    line_item
  end
end
