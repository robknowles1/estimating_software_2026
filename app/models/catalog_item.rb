class CatalogItem < ApplicationRecord
  has_many :line_items, dependent: :nullify

  validates :description, presence: true

  scope :search, ->(query) {
    where("LOWER(description) LIKE ?", "%#{query.to_s.downcase}%")
      .order(:description)
      .limit(10)
  }
end
