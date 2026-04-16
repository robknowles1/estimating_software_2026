class Product < ApplicationRecord
  has_many :line_items, dependent: :nullify

  MATERIAL_SLOTS = %i[exterior interior interior2 back banding drawers pulls hinges slides locks].freeze
  LABOR_CATEGORIES = %i[detail mill assembly customs finish install].freeze

  validates :name, presence: true
  validates :unit, presence: true

  scope :alphabetical, -> { order(:name) }
  scope :by_category,  -> { order(:category, :name) }

  # Copies all product values into a line item's flat columns.
  # Does not save — caller is responsible for persisting.
  # Does not assign product_id — the controller sets that separately.
  def apply_to(line_item)
    MATERIAL_SLOTS.each do |slot|
      line_item.public_send(:"#{slot}_description=", public_send(:"#{slot}_description"))
      line_item.public_send(:"#{slot}_unit_price=",  public_send(:"#{slot}_unit_price"))
      line_item.public_send(:"#{slot}_qty=",         public_send(:"#{slot}_qty")) unless slot == :banding
    end

    LABOR_CATEGORIES.each do |cat|
      line_item.public_send(:"#{cat}_hrs=", public_send(:"#{cat}_hrs"))
    end

    line_item.other_material_cost = other_material_cost
    line_item.equipment_hrs       = equipment_hrs
    line_item.equipment_rate      = equipment_rate
    line_item.unit                = unit
  end
end
