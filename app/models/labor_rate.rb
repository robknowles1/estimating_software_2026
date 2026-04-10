class LaborRate < ApplicationRecord
  CATEGORIES = %w[detail mill assembly customs finish install].freeze

  validates :labor_category, presence: true, inclusion: { in: CATEGORIES }, uniqueness: true
  validates :hourly_rate, numericality: { greater_than_or_equal_to: 0 }

  def self.rate_for(category)
    find_by(labor_category: category.to_s)&.hourly_rate || BigDecimal("0")
  end
end
