class MaterialSetItem < ApplicationRecord
  belongs_to :material_set
  belongs_to :material

  validates :material_id, uniqueness: { scope: :material_set_id }
end
