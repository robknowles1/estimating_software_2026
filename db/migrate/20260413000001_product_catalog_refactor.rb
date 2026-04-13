class ProductCatalogRefactor < ActiveRecord::Migration[8.1]
  def up
    # Pre-production clean break: clear all data before schema changes
    execute "DELETE FROM line_items"
    execute "DELETE FROM estimates"

    # Drop FK constraints from line_items to materials
    remove_foreign_key :line_items, column: :back_material_id
    remove_foreign_key :line_items, column: :banding_material_id
    remove_foreign_key :line_items, column: :drawers_material_id
    remove_foreign_key :line_items, column: :exterior_material_id
    remove_foreign_key :line_items, column: :hinges_material_id
    remove_foreign_key :line_items, column: :interior2_material_id
    remove_foreign_key :line_items, column: :interior_material_id
    remove_foreign_key :line_items, column: :pulls_material_id
    remove_foreign_key :line_items, column: :slides_material_id

    # Remove the 9 material FK columns from line_items
    remove_column :line_items, :exterior_material_id
    remove_column :line_items, :interior_material_id
    remove_column :line_items, :interior2_material_id
    remove_column :line_items, :back_material_id
    remove_column :line_items, :banding_material_id
    remove_column :line_items, :drawers_material_id
    remove_column :line_items, :pulls_material_id
    remove_column :line_items, :hinges_material_id
    remove_column :line_items, :slides_material_id

    # Add flat description + unit_price columns to line_items for each slot
    %w[exterior interior interior2 back banding drawers pulls hinges slides locks].each do |slot|
      add_column :line_items, :"#{slot}_description", :string
      add_column :line_items, :"#{slot}_unit_price", :decimal, precision: 12, scale: 4
    end

    # Create the products table
    create_table :products do |t|
      t.string  :name,     null: false
      t.string  :category
      t.string  :unit,     null: false, default: "EA"

      # Material slots
      %w[exterior interior interior2 back drawers pulls hinges slides locks].each do |slot|
        t.string  :"#{slot}_description"
        t.decimal :"#{slot}_unit_price", precision: 12, scale: 4
        t.decimal :"#{slot}_qty",        precision: 10, scale: 4
      end

      # Banding — flat per-unit cost, no qty
      t.string  :banding_description
      t.decimal :banding_unit_price, precision: 12, scale: 4

      t.decimal :other_material_cost, precision: 12, scale: 2

      # Labor hours
      t.decimal :detail_hrs,   precision: 8, scale: 4
      t.decimal :mill_hrs,     precision: 8, scale: 4
      t.decimal :assembly_hrs, precision: 8, scale: 4
      t.decimal :customs_hrs,  precision: 8, scale: 4
      t.decimal :finish_hrs,   precision: 8, scale: 4
      t.decimal :install_hrs,  precision: 8, scale: 4

      # Equipment
      t.decimal :equipment_hrs,  precision: 8,  scale: 4
      t.decimal :equipment_rate, precision: 10, scale: 2

      t.timestamps
    end

    add_index :products, :name
    add_index :products, :category

    # Add nullable product_id FK to line_items (ON DELETE SET NULL)
    add_column :line_items, :product_id, :bigint
    add_index  :line_items, :product_id
    add_foreign_key :line_items, :products, on_delete: :nullify

    # Drop the materials table (FK from materials to estimates removed first)
    remove_foreign_key :materials, :estimates
    drop_table :materials
  end

  def down
    raise ActiveRecord::IrreversibleMigration
  end
end
