class Product < ApplicationRecord
  has_many :line_items, dependent: :nullify

  MATERIAL_SLOTS   = %i[exterior interior interior2 back banding drawers pulls hinges slides locks].freeze
  LABOR_CATEGORIES = %i[detail mill assembly customs finish install].freeze

  validates :name, presence: true
  validates :unit, presence: true

  scope :alphabetical, -> { order(:name) }
  scope :by_category,  -> { order(:category, :name) }

  # Copies quantity and labor template values into a line item.
  # Does not set any _material_id, _unit_price, or _description values —
  # those are job-scoped and set by the estimator via the price book.
  # Does not save — caller is responsible for persisting.
  # Does not assign product_id — the controller sets that separately.
  def apply_to(line_item)
    %i[exterior interior interior2 back drawers pulls hinges slides].each do |slot|
      line_item.public_send(:"#{slot}_qty=", public_send(:"#{slot}_qty"))
    end
    line_item.locks_qty = locks_qty

    LABOR_CATEGORIES.each do |cat|
      line_item.public_send(:"#{cat}_hrs=", public_send(:"#{cat}_hrs"))
    end

    line_item.other_material_cost = other_material_cost
    line_item.equipment_hrs       = equipment_hrs
    line_item.equipment_rate      = equipment_rate
    line_item.unit                = unit
  end
end
