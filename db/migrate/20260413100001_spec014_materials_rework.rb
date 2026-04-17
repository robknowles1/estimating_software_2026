class Spec014MaterialsRework < ActiveRecord::Migration[8.1]
  def up
    # Pre-production clean break: clear all data before schema changes
    execute "DELETE FROM line_items"
    execute "DELETE FROM estimates"

    # ── 1. Remove flat _unit_price and _description columns from line_items ──
    %w[exterior interior interior2 back banding drawers pulls hinges slides locks].each do |slot|
      remove_column :line_items, :"#{slot}_description"
      remove_column :line_items, :"#{slot}_unit_price"
    end

    # ── 2. Remove flat _unit_price and _description columns from products ──
    %w[exterior interior interior2 back banding drawers pulls hinges slides locks].each do |slot|
      remove_column :products, :"#{slot}_description"
      remove_column :products, :"#{slot}_unit_price"
    end

    # ── 3. Create global materials library table ──
    create_table :materials do |t|
      t.string   :name,          null: false
      t.string   :description
      t.string   :category,      null: false
      t.string   :unit
      t.decimal  :default_price, precision: 12, scale: 4, default: "0", null: false
      t.datetime :discarded_at

      t.timestamps
    end

    add_index :materials, :name

    # ── 4. Create estimate_materials table (per-estimate pricing) ──
    create_table :estimate_materials do |t|
      t.bigint   :estimate_id,    null: false
      t.bigint   :material_id,    null: false
      t.decimal  :quote_price,    precision: 12, scale: 4, default: "0", null: false
      t.decimal  :cost_with_tax,  precision: 12, scale: 4, default: "0", null: false
      t.string   :role

      t.timestamps
    end

    add_index :estimate_materials, :estimate_id
    add_index :estimate_materials, [ :estimate_id, :material_id ], unique: true

    add_foreign_key :estimate_materials, :estimates, on_delete: :cascade
    add_foreign_key :estimate_materials, :materials

    # ── 5. Add nine _material_id FK columns to line_items ──
    %w[exterior interior interior2 back banding drawers pulls hinges slides].each do |slot|
      add_column :line_items, :"#{slot}_material_id", :bigint
    end

    # Add FKs pointing at estimate_materials with ON DELETE SET NULL
    %w[exterior interior interior2 back banding drawers pulls hinges slides].each do |slot|
      add_foreign_key :line_items, :estimate_materials,
                      column: :"#{slot}_material_id",
                      on_delete: :nullify
    end

    # ── 6. Create material_sets table ──
    create_table :material_sets do |t|
      t.string :name, null: false
      t.timestamps
    end

    # ── 7. Create material_set_items table ──
    create_table :material_set_items do |t|
      t.bigint :material_set_id, null: false
      t.bigint :material_id,     null: false
      t.timestamps
    end

    add_index :material_set_items, :material_set_id
    add_index :material_set_items, [ :material_set_id, :material_id ], unique: true

    add_foreign_key :material_set_items, :material_sets, on_delete: :cascade
    add_foreign_key :material_set_items, :materials
  end

  def down
    raise ActiveRecord::IrreversibleMigration
  end
end
