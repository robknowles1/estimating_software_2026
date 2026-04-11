# Migration 4 of 5 — Add new columns to estimates and fix TD-01.
#
# TD-01: created_by_user_id was an integer with default 0. Change to bigint,
#        drop the default. Presence is enforced at the model/controller layer only.
#
# New columns per ADR-008 Decision 5 and spec:
#   tax_rate, tax_exempt — for per-estimate tax calculation
#   install_travel_qty, delivery_qty, delivery_rate, per_diem_qty, per_diem_rate,
#   hotel_qty, airfare_qty, equipment_cost, countertop_quote — job-level cost fields
#   (UI for these is SPEC-012 scope; columns added here as the schema is built once)
#
# Also corrects default values for installer_crew_size, delivery_crew_size,
# pm_supervision_percent, and profit_overhead_percent to match the spreadsheet.
class UpdateEstimatesForRefactor < ActiveRecord::Migration[8.1]
  def up
    # Fix TD-01: drop default 0 and change to bigint
    change_column :estimates, :created_by_user_id, :bigint
    change_column_default :estimates, :created_by_user_id, from: 0, to: nil

    # Tax fields
    add_column :estimates, :tax_rate,   :decimal, precision: 5,  scale: 4, null: false, default: 0.08
    add_column :estimates, :tax_exempt, :boolean,                           null: false, default: false

    # Job-level cost qty + rate fields
    add_column :estimates, :install_travel_qty, :decimal, precision: 10, scale: 2, default: 0
    add_column :estimates, :delivery_qty,        :decimal, precision: 10, scale: 2, default: 0
    add_column :estimates, :delivery_rate,       :decimal, precision: 10, scale: 2, default: 400
    add_column :estimates, :per_diem_qty,        :decimal, precision: 10, scale: 2, default: 0
    add_column :estimates, :per_diem_rate,       :decimal, precision: 10, scale: 2, default: 65
    add_column :estimates, :hotel_qty,           :decimal, precision: 10, scale: 2, default: 0
    add_column :estimates, :airfare_qty,         :decimal, precision: 10, scale: 2, default: 0
    add_column :estimates, :equipment_cost,      :decimal, precision: 10, scale: 2, default: 0
    add_column :estimates, :countertop_quote,    :decimal, precision: 10, scale: 2, default: 0

    # Update defaults to match spreadsheet values (ADR-008 schema section)
    change_column_default :estimates, :installer_crew_size,     from: 1, to: 2
    change_column_default :estimates, :delivery_crew_size,      from: 1, to: 2
    change_column_default :estimates, :pm_supervision_percent,  from: 0.0, to: 4.00
    change_column_default :estimates, :profit_overhead_percent, from: 0.0, to: 10.00
  end

  def down
    remove_column :estimates, :tax_rate
    remove_column :estimates, :tax_exempt
    remove_column :estimates, :install_travel_qty
    remove_column :estimates, :delivery_qty
    remove_column :estimates, :delivery_rate
    remove_column :estimates, :per_diem_qty
    remove_column :estimates, :per_diem_rate
    remove_column :estimates, :hotel_qty
    remove_column :estimates, :airfare_qty
    remove_column :estimates, :equipment_cost
    remove_column :estimates, :countertop_quote

    change_column_default :estimates, :installer_crew_size,     from: 2, to: 1
    change_column_default :estimates, :delivery_crew_size,      from: 2, to: 1
    change_column_default :estimates, :pm_supervision_percent,  from: 4.00, to: 0.0
    change_column_default :estimates, :profit_overhead_percent, from: 10.00, to: 0.0

    change_column :estimates, :created_by_user_id, :integer
    change_column_default :estimates, :created_by_user_id, from: nil, to: 0
  end
end
