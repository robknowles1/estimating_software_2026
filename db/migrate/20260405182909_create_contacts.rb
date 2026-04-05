class CreateContacts < ActiveRecord::Migration[8.1]
  def change
    create_table :contacts do |t|
      t.references :client, null: false, foreign_key: true
      t.string :first_name, null: false
      t.string :last_name, null: false
      t.string :title
      t.string :email
      t.string :phone
      t.boolean :is_primary, null: false, default: false
      t.text :notes

      t.timestamps
    end

    # Partial unique index: at most one primary contact per client (PostgreSQL)
    add_index :contacts, :client_id,
      where: "is_primary = TRUE",
      unique: true,
      name: "index_contacts_on_client_id_primary"
  end
end
