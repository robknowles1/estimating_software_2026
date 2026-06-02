class AddSlotCodeColumnsToProducts < ActiveRecord::Migration[8.1]
  def change
    add_column :products, :exterior_slot_code, :string
    add_column :products, :interior_slot_code, :string
    add_column :products, :interior2_slot_code, :string
    add_column :products, :back_slot_code, :string
    add_column :products, :banding_slot_code, :string
    add_column :products, :drawers_slot_code, :string
    add_column :products, :pulls_slot_code, :string
    add_column :products, :hinges_slot_code, :string
    add_column :products, :slides_slot_code, :string
    add_column :products, :locks_slot_code, :string
  end
end
