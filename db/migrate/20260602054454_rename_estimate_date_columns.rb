class RenameEstimateDateColumns < ActiveRecord::Migration[8.1]
  def change
    rename_column :estimates, :job_start_date, :bid_due_date
    rename_column :estimates, :job_end_date,   :job_start_date
  end
end
