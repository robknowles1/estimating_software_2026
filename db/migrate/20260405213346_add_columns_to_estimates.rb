class AddColumnsToEstimates < ActiveRecord::Migration[8.1]
  def change
    add_column :estimates, :title, :string, null: false, default: ""
    add_column :estimates, :estimate_number, :string, null: false, default: ""
    add_column :estimates, :status, :string, null: false, default: "draft"
    add_column :estimates, :created_by_user_id, :integer, null: false, default: 0
    add_column :estimates, :job_start_date, :date
    add_column :estimates, :job_end_date, :date
    add_column :estimates, :notes, :text
    add_column :estimates, :client_notes, :text

    add_index :estimates, :estimate_number, unique: true
    add_index :estimates, :status
    add_index :estimates, :updated_at
    add_index :estimates, :created_by_user_id

    add_foreign_key :estimates, :users, column: :created_by_user_id
  end
end
