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

  # +estimate_or_index+ may be an Estimate (code index built from DB) or a
  # pre-built Hash<String, EstimateMaterial> passed in to avoid an extra DB
  # query when the same estimate is used across many rows (e.g. CSV import).
  def initialize(product, estimate_or_index)
    @product = product
    @code_index =
      if estimate_or_index.is_a?(Hash)
        estimate_or_index
      else
        self.class.build_code_index(estimate_or_index)
      end
  end

  # Builds a Hash<String (downcased short_code), EstimateMaterial> from the
  # estimate's price book entries. When the estimate_materials association is
  # already loaded (e.g. via LineItemsController#set_estimate's includes(...)),
  # filters blank short codes in Ruby to avoid a redundant SQL query. Falls
  # back to a SQL filter when the association is not loaded.
  #
  # Exposed as a class method so callers that build their own resolver cache
  # (e.g. LineItemCsvImporter) can share the same loaded?/SQL branching logic.
  def self.build_code_index(estimate)
    scope = estimate.estimate_materials

    records =
      if scope.loaded?
        scope.reject { |em| em.short_code.to_s.strip.empty? }
      else
        scope.where.not(short_code: [ nil, "" ])
      end

    records.index_by { |em| em.short_code.downcase }
  end

  def call(line_item)
    return line_item if @code_index.empty?

    SLOT_MAP.each do |slot, code_attr|
      hint = @product.public_send(code_attr).to_s.strip.downcase
      next if hint.blank?

      matched = @code_index[hint]
      next unless matched

      line_item.public_send(:"#{slot}_material_id=", matched.id)
    end

    line_item
  end
end
