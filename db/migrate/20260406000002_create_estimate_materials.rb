class CreateEstimateMaterials < ActiveRecord::Migration[8.1]
  def change
    create_table :estimate_materials do |t|
      t.references :estimate, null: false, foreign_key: { on_delete: :cascade }
      t.string :category, null: false
      t.integer :slot_number, null: false
      t.string :description
      t.decimal :price_per_unit, precision: 10, scale: 4, null: false, default: "0.0"
      t.string :unit
      # catalog_item_id references material_catalog_items introduced in Phase 5.
      # That table does not exist in Phase 4. Do NOT add a DB-level FK here.
      # Phase 5 adds the FK constraint when the referenced table is created.
      t.integer :catalog_item_id
      t.date :last_priced_at

      t.timestamps
    end

    add_index :estimate_materials, [ :estimate_id, :category, :slot_number ], unique: true, name: "index_estimate_materials_on_estimate_category_slot"
    add_index :estimate_materials, :catalog_item_id
  end
end
