class CreateClients < ActiveRecord::Migration[8.1]
  def change
    create_table :clients do |t|
      t.string :company_name, null: false
      t.string :address
      t.text :notes

      t.timestamps
    end

    add_index :clients, :company_name
  end
end
