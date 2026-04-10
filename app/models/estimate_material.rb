class EstimateMaterial < ApplicationRecord
  belongs_to :estimate

  CATEGORIES = %w[pl pull hinge slide banding veneer].freeze

  validates :category, presence: true, inclusion: { in: CATEGORIES }
  validates :slot_number, presence: true, numericality: { only_integer: true, greater_than_or_equal_to: 1, less_than_or_equal_to: 6 }
  validates :price_per_unit, numericality: { greater_than_or_equal_to: 0 }
  validates :slot_number, uniqueness: { scope: [ :estimate_id, :category ] }

  def slot_label
    "#{category.upcase}#{slot_number}"
  end
end
