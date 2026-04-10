class AddNotNullToLineItemDescription < ActiveRecord::Migration[8.1]
  def change
    # Fill any existing nulls with empty string before adding the constraint.
    # The model validates presence so empty string is still invalid at app level,
    # but this prevents the migration from failing on a populated dev database.
    change_column_null :line_items, :description, false, ""
  end
end
