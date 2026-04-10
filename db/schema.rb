# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[8.1].define(version: 2026_04_10_171316) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "plpgsql"

  create_table "clients", force: :cascade do |t|
    t.string "address"
    t.string "company_name", null: false
    t.datetime "created_at", null: false
    t.text "notes"
    t.datetime "updated_at", null: false
    t.index ["company_name"], name: "index_clients_on_company_name"
  end

  create_table "contacts", force: :cascade do |t|
    t.bigint "client_id", null: false
    t.datetime "created_at", null: false
    t.string "email"
    t.string "first_name", null: false
    t.boolean "is_primary", default: false, null: false
    t.string "last_name", null: false
    t.text "notes"
    t.string "phone"
    t.string "title"
    t.datetime "updated_at", null: false
    t.index ["client_id"], name: "index_contacts_on_client_id"
    t.index ["client_id"], name: "index_contacts_on_client_id_primary", unique: true, where: "(is_primary = true)"
  end

  create_table "estimate_materials", force: :cascade do |t|
    t.integer "catalog_item_id"
    t.string "category", null: false
    t.datetime "created_at", null: false
    t.string "description"
    t.bigint "estimate_id", null: false
    t.date "last_priced_at"
    t.decimal "price_per_unit", precision: 10, scale: 4, default: "0.0", null: false
    t.integer "slot_number", null: false
    t.string "unit"
    t.datetime "updated_at", null: false
    t.index ["catalog_item_id"], name: "index_estimate_materials_on_catalog_item_id"
    t.index ["estimate_id", "category", "slot_number"], name: "index_estimate_materials_on_estimate_category_slot", unique: true
    t.index ["estimate_id"], name: "index_estimate_materials_on_estimate_id"
  end

  create_table "estimate_sections", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.decimal "default_markup_percent", precision: 5, scale: 2, default: "0.0", null: false
    t.bigint "estimate_id", null: false
    t.string "name", default: "", null: false
    t.integer "position", default: 0, null: false
    t.decimal "quantity", precision: 10, scale: 2, default: "1.0", null: false
    t.datetime "updated_at", null: false
    t.index ["estimate_id", "position"], name: "index_estimate_sections_on_estimate_id_and_position"
    t.index ["estimate_id"], name: "index_estimate_sections_on_estimate_id"
  end

  create_table "estimates", force: :cascade do |t|
    t.bigint "client_id", null: false
    t.text "client_notes"
    t.datetime "created_at", null: false
    t.integer "created_by_user_id", default: 0, null: false
    t.integer "delivery_crew_size", default: 1, null: false
    t.string "estimate_number", default: "", null: false
    t.integer "installer_crew_size", default: 1, null: false
    t.date "job_end_date"
    t.date "job_start_date"
    t.decimal "miles_to_jobsite", precision: 8, scale: 2
    t.text "notes"
    t.decimal "on_site_time_hrs", precision: 6, scale: 2
    t.decimal "pm_supervision_percent", precision: 5, scale: 2, default: "0.0", null: false
    t.decimal "profit_overhead_percent", precision: 5, scale: 2, default: "0.0", null: false
    t.string "status", default: "draft", null: false
    t.string "title", default: "", null: false
    t.datetime "updated_at", null: false
    t.index ["client_id"], name: "index_estimates_on_client_id"
    t.index ["created_by_user_id"], name: "index_estimates_on_created_by_user_id"
    t.index ["estimate_number"], name: "index_estimates_on_estimate_number", unique: true
    t.index ["status"], name: "index_estimates_on_status"
    t.index ["updated_at"], name: "index_estimates_on_updated_at"
  end

  create_table "labor_rates", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "description"
    t.decimal "hourly_rate", precision: 10, scale: 4, default: "0.0", null: false
    t.string "labor_category", null: false
    t.datetime "updated_at", null: false
    t.index ["labor_category"], name: "index_labor_rates_on_labor_category", unique: true
  end

  create_table "line_items", force: :cascade do |t|
    t.integer "catalog_item_id"
    t.decimal "component_quantity", precision: 10, scale: 4
    t.string "component_type"
    t.string "cost_type"
    t.datetime "created_at", null: false
    t.string "description", null: false
    t.integer "estimate_material_id"
    t.bigint "estimate_section_id", null: false
    t.decimal "freeform_quantity", precision: 10, scale: 4
    t.decimal "hours_per_unit", precision: 8, scale: 4
    t.string "labor_category"
    t.string "line_item_category", default: "material", null: false
    t.decimal "markup_percent", precision: 5, scale: 2, default: "0.0"
    t.text "notes"
    t.integer "position", default: 0, null: false
    t.string "unit"
    t.decimal "unit_cost", precision: 10, scale: 4, default: "0.0"
    t.datetime "updated_at", null: false
    t.index ["catalog_item_id"], name: "index_line_items_on_catalog_item_id"
    t.index ["estimate_material_id"], name: "index_line_items_on_estimate_material_id"
    t.index ["estimate_section_id", "position"], name: "index_line_items_on_estimate_section_id_and_position"
    t.index ["estimate_section_id"], name: "index_line_items_on_estimate_section_id"
    t.index ["line_item_category"], name: "index_line_items_on_line_item_category"
  end

  create_table "users", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "email", null: false
    t.string "name", null: false
    t.string "password_digest", null: false
    t.datetime "updated_at", null: false
    t.index ["email"], name: "index_users_on_email", unique: true
  end

  add_foreign_key "contacts", "clients"
  add_foreign_key "estimate_materials", "estimates", on_delete: :cascade
  add_foreign_key "estimate_sections", "estimates"
  add_foreign_key "estimates", "clients"
  add_foreign_key "estimates", "users", column: "created_by_user_id"
  add_foreign_key "line_items", "estimate_materials", on_delete: :nullify
  add_foreign_key "line_items", "estimate_sections"
end
