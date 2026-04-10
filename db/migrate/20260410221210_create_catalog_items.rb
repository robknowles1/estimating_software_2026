class CreateCatalogItems < ActiveRecord::Migration[8.1]
  def change
    create_table :catalog_items do |t|
      t.string :description, null: false
      t.string :default_unit
      t.decimal :default_unit_cost, precision: 10, scale: 2
      t.string :category

      t.timestamps
    end

    add_index :catalog_items, :description
    add_index :catalog_items, :category
  end
end
