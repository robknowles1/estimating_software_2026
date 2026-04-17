class EstimateMaterial < ApplicationRecord
  belongs_to :estimate
  belongs_to :material

  ROLES = %w[locks].freeze

  validates :quote_price,  numericality: { greater_than_or_equal_to: 0 }
  validates :material_id,  uniqueness: { scope: :estimate_id }
  validates :role,         inclusion: { in: ROLES }, allow_nil: true

  before_save :compute_cost_with_tax

  private

  def compute_cost_with_tax
    self.cost_with_tax = if estimate.tax_exempt?
                           quote_price
    else
                           quote_price * (BigDecimal("1") + estimate.tax_rate.to_d)
    end
  end
end
