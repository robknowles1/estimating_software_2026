# LineItem represents one finished product row on an estimate.
#
# Column groups:
#   Core:       description, quantity, unit, position
#   Material FKs (nullable, ON DELETE SET NULL):
#               exterior_material_id, interior_material_id, interior2_material_id,
#               back_material_id, banding_material_id (no qty — on/off type selection),
#               drawers_material_id, pulls_material_id, hinges_material_id, slides_material_id
#   Material Qtys (nullable):
#               exterior_qty, interior_qty, interior2_qty, back_qty, drawers_qty,
#               pulls_qty, hinges_qty, slides_qty, locks_qty
#               (banding has no qty per ADR-008; locks has qty but no material FK —
#               its price comes from the LOCKS slot on materials)
#   Other cost: other_material_cost — freeform per-unit cost
#   Labor hrs:  detail_hrs, mill_hrs, assembly_hrs, customs_hrs, finish_hrs, install_hrs
#   Equipment:  equipment_hrs, equipment_rate
#
# Calculated fields (not stored, computed in EstimateTotalsCalculator):
#   material_cost_per_unit, subtotal_materials, labor subtotals, burdened_total
class LineItem < ApplicationRecord
  belongs_to :estimate

  belongs_to :exterior_material,  class_name: "Material", optional: true, foreign_key: :exterior_material_id
  belongs_to :interior_material,  class_name: "Material", optional: true, foreign_key: :interior_material_id
  belongs_to :interior2_material, class_name: "Material", optional: true, foreign_key: :interior2_material_id
  belongs_to :back_material,      class_name: "Material", optional: true, foreign_key: :back_material_id
  belongs_to :banding_material,   class_name: "Material", optional: true, foreign_key: :banding_material_id
  belongs_to :drawers_material,   class_name: "Material", optional: true, foreign_key: :drawers_material_id
  belongs_to :pulls_material,     class_name: "Material", optional: true, foreign_key: :pulls_material_id
  belongs_to :hinges_material,    class_name: "Material", optional: true, foreign_key: :hinges_material_id
  belongs_to :slides_material,    class_name: "Material", optional: true, foreign_key: :slides_material_id

  acts_as_list scope: :estimate

  validates :description, presence: true
  validates :quantity, presence: true, numericality: { greater_than: 0 }
end
