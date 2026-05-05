class AddOtherMaterialSlotToLineItems < ActiveRecord::Migration[8.1]
  def change
    add_column :line_items, :other_material_id, :bigint
    add_column :line_items, :other_qty, :decimal, precision: 10, scale: 4

    add_foreign_key :line_items, :estimate_materials,
                    column: :other_material_id,
                    on_delete: :nullify

    add_index :line_items, :other_material_id, name: "index_line_items_on_other_material_id"
  end
end
