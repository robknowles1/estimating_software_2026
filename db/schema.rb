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

ActiveRecord::Schema[8.1].define(version: 2026_04_11_000005) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "plpgsql"

  create_table "clients", force: :cascade do |t|
    t.string "address"
    t.string "company_name", null: false
    t.datetime "created_at", null: false
    t.text "notes"
    t.boolean "tax_exempt", default: false, null: false
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

  create_table "estimates", force: :cascade do |t|
    t.decimal "airfare_qty", precision: 10, scale: 2, default: "0.0"
    t.bigint "client_id", null: false
    t.text "client_notes"
    t.decimal "countertop_quote", precision: 10, scale: 2, default: "0.0"
    t.datetime "created_at", null: false
    t.bigint "created_by_user_id", null: false
    t.integer "delivery_crew_size", default: 2, null: false
    t.decimal "delivery_qty", precision: 10, scale: 2, default: "0.0"
    t.decimal "delivery_rate", precision: 10, scale: 2, default: "400.0"
    t.decimal "equipment_cost", precision: 10, scale: 2, default: "0.0"
    t.string "estimate_number", default: "", null: false
    t.decimal "hotel_qty", precision: 10, scale: 2, default: "0.0"
    t.decimal "install_travel_qty", precision: 10, scale: 2, default: "0.0"
    t.integer "installer_crew_size", default: 2, null: false
    t.date "job_end_date"
    t.date "job_start_date"
    t.decimal "miles_to_jobsite", precision: 8, scale: 2
    t.text "notes"
    t.decimal "on_site_time_hrs", precision: 6, scale: 2
    t.decimal "per_diem_qty", precision: 10, scale: 2, default: "0.0"
    t.decimal "per_diem_rate", precision: 10, scale: 2, default: "65.0"
    t.decimal "pm_supervision_percent", precision: 5, scale: 2, default: "4.0", null: false
    t.decimal "profit_overhead_percent", precision: 5, scale: 2, default: "10.0", null: false
    t.string "status", default: "draft", null: false
    t.boolean "tax_exempt", default: false, null: false
    t.decimal "tax_rate", precision: 5, scale: 4, default: "0.08", null: false
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
    t.decimal "assembly_hrs", precision: 10, scale: 4
    t.bigint "back_material_id"
    t.decimal "back_qty", precision: 10, scale: 4
    t.bigint "banding_material_id"
    t.datetime "created_at", null: false
    t.decimal "customs_hrs", precision: 10, scale: 4
    t.string "description", null: false
    t.decimal "detail_hrs", precision: 10, scale: 4
    t.bigint "drawers_material_id"
    t.decimal "drawers_qty", precision: 10, scale: 4
    t.decimal "equipment_hrs", precision: 10, scale: 4
    t.decimal "equipment_rate", precision: 10, scale: 2
    t.bigint "estimate_id", null: false
    t.bigint "exterior_material_id"
    t.decimal "exterior_qty", precision: 10, scale: 4
    t.decimal "finish_hrs", precision: 10, scale: 4
    t.bigint "hinges_material_id"
    t.decimal "hinges_qty", precision: 10, scale: 4
    t.decimal "install_hrs", precision: 10, scale: 4
    t.bigint "interior2_material_id"
    t.decimal "interior2_qty", precision: 10, scale: 4
    t.bigint "interior_material_id"
    t.decimal "interior_qty", precision: 10, scale: 4
    t.decimal "locks_qty", precision: 10, scale: 4
    t.decimal "mill_hrs", precision: 10, scale: 4
    t.decimal "other_material_cost", precision: 10, scale: 2
    t.integer "position"
    t.bigint "pulls_material_id"
    t.decimal "pulls_qty", precision: 10, scale: 4
    t.decimal "quantity", precision: 10, scale: 4, default: "1.0", null: false
    t.bigint "slides_material_id"
    t.decimal "slides_qty", precision: 10, scale: 4
    t.string "unit", default: "EA"
    t.datetime "updated_at", null: false
    t.index ["estimate_id", "position"], name: "index_line_items_on_estimate_id_and_position"
    t.index ["estimate_id"], name: "index_line_items_on_estimate_id"
  end

  create_table "materials", force: :cascade do |t|
    t.string "category", null: false
    t.decimal "cost_with_tax", precision: 12, scale: 4, default: "0.0", null: false
    t.datetime "created_at", null: false
    t.string "description"
    t.bigint "estimate_id", null: false
    t.decimal "quote_price", precision: 12, scale: 4, default: "0.0", null: false
    t.string "slot_key", null: false
    t.datetime "updated_at", null: false
    t.index ["estimate_id", "slot_key"], name: "index_materials_on_estimate_id_and_slot_key", unique: true
    t.index ["estimate_id"], name: "index_materials_on_estimate_id"
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
  add_foreign_key "estimates", "clients"
  add_foreign_key "estimates", "users", column: "created_by_user_id"
  add_foreign_key "line_items", "estimates", on_delete: :cascade
  add_foreign_key "line_items", "materials", column: "back_material_id", on_delete: :nullify
  add_foreign_key "line_items", "materials", column: "banding_material_id", on_delete: :nullify
  add_foreign_key "line_items", "materials", column: "drawers_material_id", on_delete: :nullify
  add_foreign_key "line_items", "materials", column: "exterior_material_id", on_delete: :nullify
  add_foreign_key "line_items", "materials", column: "hinges_material_id", on_delete: :nullify
  add_foreign_key "line_items", "materials", column: "interior2_material_id", on_delete: :nullify
  add_foreign_key "line_items", "materials", column: "interior_material_id", on_delete: :nullify
  add_foreign_key "line_items", "materials", column: "pulls_material_id", on_delete: :nullify
  add_foreign_key "line_items", "materials", column: "slides_material_id", on_delete: :nullify
  add_foreign_key "materials", "estimates", on_delete: :cascade
end
