class CreateLineItems < ActiveRecord::Migration[8.1]
  def change
    create_table :line_items do |t|
      t.references :estimate_section, null: false, foreign_key: true
      t.string :description
      t.string :line_item_category, null: false, default: "material"
      t.string :component_type
      t.string :labor_category
      # estimate_material_id FK uses ON DELETE NULLIFY: if a material slot is deleted,
      # the line item survives with estimate_material_id: nil rather than being destroyed.
      t.integer :estimate_material_id
      t.decimal :component_quantity, precision: 10, scale: 4
      t.decimal :hours_per_unit, precision: 8, scale: 4
      t.decimal :freeform_quantity, precision: 10, scale: 4
      t.decimal :unit_cost, precision: 10, scale: 4, default: "0.0"
      t.decimal :markup_percent, precision: 5, scale: 2, default: "0.0"
      t.string :unit
      t.text :notes
      t.string :cost_type
      # catalog_item_id references material_catalog_items introduced in Phase 5.
      # No DB-level FK here — Phase 5 adds the constraint when the table is created.
      t.integer :catalog_item_id
      t.integer :position, null: false, default: 0

      t.timestamps
    end

    add_index :line_items, [ :estimate_section_id, :position ]
    add_index :line_items, :estimate_material_id
    add_index :line_items, :line_item_category
    add_index :line_items, :catalog_item_id

    add_foreign_key :line_items, :estimate_materials, on_delete: :nullify
  end
end
