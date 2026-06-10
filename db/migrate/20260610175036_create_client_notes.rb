class CreateClientNotes < ActiveRecord::Migration[8.1]
  def change
    create_table :client_notes do |t|
      t.references :client, null: false, foreign_key: true
      t.text :body, null: false

      t.timestamps
    end
  end
end
