class AddJobSettingsToEstimates < ActiveRecord::Migration[8.1]
  def change
    add_column :estimates, :miles_to_jobsite, :decimal, precision: 8, scale: 2
    add_column :estimates, :installer_crew_size, :integer, null: false, default: 1
    add_column :estimates, :delivery_crew_size, :integer, null: false, default: 1
    add_column :estimates, :on_site_time_hrs, :decimal, precision: 6, scale: 2
    add_column :estimates, :profit_overhead_percent, :decimal, precision: 5, scale: 2, null: false, default: "0.0"
    add_column :estimates, :pm_supervision_percent, :decimal, precision: 5, scale: 2, null: false, default: "0.0"
  end
end
