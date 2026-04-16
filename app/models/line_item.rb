# LineItem represents one finished product row on an estimate.
#
# Column groups:
#   Core:                description, quantity, unit, position
#   Catalog Reference:   product_id (nullable FK to products, ON DELETE SET NULL;
#                        display/audit only — not used by calculator)
#   Material Descriptions + Unit Prices (flat columns, per-slot):
#               exterior_description, exterior_unit_price
#               interior_description, interior_unit_price
#               interior2_description, interior2_unit_price
#               back_description, back_unit_price
#               banding_description, banding_unit_price  (no qty — flat per-unit cost)
#               drawers_description, drawers_unit_price
#               pulls_description, pulls_unit_price
#               hinges_description, hinges_unit_price
#               slides_description, slides_unit_price
#               locks_description, locks_unit_price
#   Material Quantities (nullable):
#               exterior_qty, interior_qty, interior2_qty, back_qty,
#               drawers_qty, pulls_qty, hinges_qty, slides_qty, locks_qty
#               (banding has no qty per ADR-008)
#   Other cost: other_material_cost — freeform per-unit cost
#   Labor hrs:  detail_hrs, mill_hrs, assembly_hrs, customs_hrs, finish_hrs, install_hrs
#   Equipment:  equipment_hrs, equipment_rate
#
# Calculated fields (not stored, computed in EstimateTotalsCalculator):
#   material_cost_per_unit, subtotal_materials, labor subtotals, non_burdened_total
class LineItem < ApplicationRecord
  belongs_to :estimate
  belongs_to :product, optional: true

  acts_as_list scope: :estimate

  validates :description, presence: true
  validates :quantity,    presence: true, numericality: { greater_than: 0 }
  validates :unit,        presence: true
end
