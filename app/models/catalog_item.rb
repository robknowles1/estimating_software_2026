class CatalogItem < ApplicationRecord
  has_many :line_items, dependent: :nullify

  validates :description, presence: true

  scope :search, ->(query) {
    sanitized = query.to_s.downcase.gsub("%", "\\%").gsub("_", "\\_")
    where("LOWER(description) LIKE ? ESCAPE '\\'", "%#{sanitized}%")
      .order(:description)
      .limit(10)
  }
end
