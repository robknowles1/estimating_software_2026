class CreateProposalTables < ActiveRecord::Migration[8.1]
  def change
    create_table :proposals do |t|
      t.references :estimate, null: false, foreign_key: { on_delete: :cascade }, index: { unique: true }
      t.references :contact, foreign_key: { on_delete: :nullify }
      t.string  :mode,                   null: false, default: "commercial"
      t.string  :status,                 null: false, default: "draft"
      t.string  :job_name
      t.date    :plan_date
      t.text    :addendum_list
      t.decimal :total_amount,           precision: 12, scale: 2
      t.boolean :include_specifications, null: false, default: false
      t.text    :payment_terms
      t.string  :current_step,           null: false, default: "opening"
      t.timestamps
    end

    create_table :proposal_inclusions do |t|
      t.references :proposal, null: false, foreign_key: { on_delete: :cascade }
      t.string  :room_name, null: false
      t.text    :bullet_points
      t.integer :position
      t.timestamps
    end

    create_table :proposal_clarifications do |t|
      t.references :proposal, null: false, foreign_key: { on_delete: :cascade }
      t.text    :body,     null: false
      t.integer :position
      t.timestamps
    end

    create_table :proposal_exclusions do |t|
      t.references :proposal, null: false, foreign_key: { on_delete: :cascade }
      t.text    :body,     null: false
      t.integer :position
      t.timestamps
    end

    create_table :proposal_alternates do |t|
      t.references :proposal,   null: false, foreign_key: { on_delete: :cascade }
      t.references :line_item,  foreign_key: { on_delete: :nullify }
      t.string  :description,  null: false
      t.decimal :display_cost, null: false, precision: 12, scale: 2
      t.integer :position
      t.timestamps
    end

    create_table :proposal_specifications do |t|
      t.references :proposal, null: false, foreign_key: { on_delete: :cascade }
      t.string  :spec_number, null: false
      t.string  :spec_title,  null: false
      t.integer :position
      t.timestamps
    end
  end
end
