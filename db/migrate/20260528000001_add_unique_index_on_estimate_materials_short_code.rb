class AddUniqueIndexOnEstimateMaterialsShortCode < ActiveRecord::Migration[8.1]
  def change
    add_index :estimate_materials, [ :estimate_id, :short_code ],
              unique: true,
              where: "short_code IS NOT NULL",
              name: "index_estimate_materials_on_estimate_id_and_short_code_unique"
  end
end
