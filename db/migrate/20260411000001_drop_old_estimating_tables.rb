# Migration 1 of 5 — Drop tables from the old estimating model.
# ADR-008: EstimateSection, EstimateMaterial, and CatalogItem are all removed.
# No production data exists; clean drop is safe and correct.
class DropOldEstimatingTables < ActiveRecord::Migration[8.1]
  def up
    # Remove FK from line_items before dropping referenced tables
    remove_foreign_key :line_items, :estimate_materials if foreign_key_exists?(:line_items, :estimate_materials)
    remove_foreign_key :line_items, :estimate_sections if foreign_key_exists?(:line_items, :estimate_sections)
    remove_foreign_key :estimate_sections, :estimates if foreign_key_exists?(:estimate_sections, :estimates)
    remove_foreign_key :estimate_materials, :estimates if foreign_key_exists?(:estimate_materials, :estimates)

    drop_table :line_items, if_exists: true
    drop_table :estimate_sections, if_exists: true
    drop_table :estimate_materials, if_exists: true
    drop_table :catalog_items, if_exists: true
  end

  def down
    raise ActiveRecord::IrreversibleMigration
  end
end
