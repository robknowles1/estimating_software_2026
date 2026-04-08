class CreateEstimateSections < ActiveRecord::Migration[8.1]
  def change
    create_table :estimate_sections do |t|
      t.references :estimate, null: false, foreign_key: true
      t.string :name, null: false, default: ""
      t.integer :position, null: false, default: 0
      t.decimal :default_markup_percent, precision: 5, scale: 2, null: false, default: 0.0

      t.timestamps
    end

    add_index :estimate_sections, [ :estimate_id, :position ]
  end
end
