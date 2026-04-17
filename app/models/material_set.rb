class MaterialSet < ApplicationRecord
  has_many :material_set_items, dependent: :destroy
  has_many :materials, through: :material_set_items

  validates :name, presence: true
end
