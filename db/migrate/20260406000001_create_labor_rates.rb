class CreateLaborRates < ActiveRecord::Migration[8.1]
  def change
    create_table :labor_rates do |t|
      t.string :labor_category, null: false
      t.decimal :hourly_rate, precision: 10, scale: 4, null: false, default: "0.0"
      t.string :description

      t.timestamps
    end

    add_index :labor_rates, :labor_category, unique: true
  end
end
