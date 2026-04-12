# Migration 3 of 5 — Rebuild line_items with the flat column schema from ADR-008.
# Each row is one finished product; material components are columns, not rows.
# All material_id FKs use ON DELETE SET NULL so deleting a material slot does not
# cascade-delete the product row.
class RebuildLineItems < ActiveRecord::Migration[8.1]
  def change
    create_table :line_items do |t|
      t.bigint  :estimate_id,  null: false
      t.string  :description,  null: false
      t.decimal :quantity,     precision: 10, scale: 4, null: false, default: 1
      t.string  :unit,                                  default: "EA"
      t.integer :position

      # Material component FKs — all nullable; ON DELETE SET NULL
      t.bigint  :exterior_material_id
      t.bigint  :interior_material_id
      t.bigint  :interior2_material_id
      t.bigint  :back_material_id
      t.bigint  :banding_material_id
      t.bigint  :drawers_material_id
      t.bigint  :pulls_material_id
      t.bigint  :hinges_material_id
      t.bigint  :slides_material_id

      # Material component quantities (no qty for banding per ADR-008)
      t.decimal :exterior_qty,  precision: 10, scale: 4
      t.decimal :interior_qty,  precision: 10, scale: 4
      t.decimal :interior2_qty, precision: 10, scale: 4
      t.decimal :back_qty,      precision: 10, scale: 4
      t.decimal :drawers_qty,   precision: 10, scale: 4
      t.decimal :pulls_qty,     precision: 10, scale: 4
      t.decimal :hinges_qty,    precision: 10, scale: 4
      t.decimal :slides_qty,    precision: 10, scale: 4
      t.decimal :locks_qty,     precision: 10, scale: 4

      t.decimal :other_material_cost, precision: 10, scale: 2

      # Labor hours per trade category
      t.decimal :detail_hrs,   precision: 10, scale: 4
      t.decimal :mill_hrs,     precision: 10, scale: 4
      t.decimal :assembly_hrs, precision: 10, scale: 4
      t.decimal :customs_hrs,  precision: 10, scale: 4
      t.decimal :finish_hrs,   precision: 10, scale: 4
      t.decimal :install_hrs,  precision: 10, scale: 4

      # Equipment
      t.decimal :equipment_hrs,  precision: 10, scale: 4
      t.decimal :equipment_rate, precision: 10, scale: 2

      t.timestamps
    end

    add_index :line_items, :estimate_id
    add_index :line_items, [ :estimate_id, :position ]

    add_foreign_key :line_items, :estimates, on_delete: :cascade
    add_foreign_key :line_items, :materials, column: :exterior_material_id,  on_delete: :nullify
    add_foreign_key :line_items, :materials, column: :interior_material_id,  on_delete: :nullify
    add_foreign_key :line_items, :materials, column: :interior2_material_id, on_delete: :nullify
    add_foreign_key :line_items, :materials, column: :back_material_id,      on_delete: :nullify
    add_foreign_key :line_items, :materials, column: :banding_material_id,   on_delete: :nullify
    add_foreign_key :line_items, :materials, column: :drawers_material_id,   on_delete: :nullify
    add_foreign_key :line_items, :materials, column: :pulls_material_id,     on_delete: :nullify
    add_foreign_key :line_items, :materials, column: :hinges_material_id,    on_delete: :nullify
    add_foreign_key :line_items, :materials, column: :slides_material_id,    on_delete: :nullify
  end
end
