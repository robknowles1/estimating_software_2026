class AddShortCodeToEstimateMaterials < ActiveRecord::Migration[8.1]
  def change
    add_column :estimate_materials, :short_code, :string
  end
end
