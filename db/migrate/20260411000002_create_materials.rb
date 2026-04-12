# Migration 2 of 5 — Create the new materials table (replaces estimate_materials).
# ADR-008 Decision 4: string slot_key instead of category + slot_number integers.
# cost_with_tax is stored for read performance; recomputed via callbacks on save.
class CreateMaterials < ActiveRecord::Migration[8.1]
  def change
    create_table :materials do |t|
      t.bigint  :estimate_id, null: false
      t.string  :slot_key,    null: false
      t.string  :category,    null: false
      t.string  :description
      t.decimal :quote_price,    precision: 12, scale: 4, null: false, default: 0
      t.decimal :cost_with_tax,  precision: 12, scale: 4, null: false, default: 0
      t.timestamps
    end

    add_index    :materials, :estimate_id
    add_index    :materials, [ :estimate_id, :slot_key ], unique: true
    add_foreign_key :materials, :estimates, on_delete: :cascade
  end
end
