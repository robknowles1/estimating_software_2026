class Material < ApplicationRecord
  has_many :estimate_materials
  has_many :material_set_items

  validates :name,          presence: true
  validates :category,      inclusion: { in: %w[sheet_good hardware] }
  validates :default_price, numericality: { greater_than_or_equal_to: 0 }

  scope :active, -> { where(discarded_at: nil) }
  scope :search, ->(term) { active.where("name ILIKE :q OR description ILIKE :q", q: "%#{term}%") }

  # Soft-deletes the material. Returns false (with a base error) if any
  # estimate_materials rows reference it — those prices must remain intact.
  def discard!
    if estimate_materials.any?
      errors.add(:base, :in_use_on_estimates,
                 message: "cannot be archived because it is in use on one or more estimates")
      return false
    end
    update(discarded_at: Time.current)
  end
end
