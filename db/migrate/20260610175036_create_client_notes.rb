class CreateClientNotes < ActiveRecord::Migration[8.1]
  def change
    create_table :client_notes do |t|
      t.references :client, null: false, foreign_key: true, index: false
      t.text :body, null: false

      t.timestamps

      t.index [ :client_id, :created_at ]
    end
  end
end
