class AddQuantityToEstimateSections < ActiveRecord::Migration[8.1]
  def change
    add_column :estimate_sections, :quantity, :decimal, precision: 10, scale: 2, null: false, default: "1.0"
  end
end
