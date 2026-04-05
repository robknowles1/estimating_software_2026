class CreateEstimates < ActiveRecord::Migration[8.1]
  # Minimal stub table for Phase 2. Full schema is built in SPEC-005 (Phase 3).
  def change
    create_table :estimates do |t|
      t.references :client, null: false, foreign_key: true

      t.timestamps
    end
  end
end
