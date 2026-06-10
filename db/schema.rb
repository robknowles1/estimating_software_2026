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

ActiveRecord::Schema[8.1].define(version: 2026_06_10_175036) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "pg_catalog.plpgsql"

  create_table "active_storage_attachments", force: :cascade do |t|
    t.bigint "blob_id", null: false
    t.datetime "created_at", null: false
    t.string "name", null: false
    t.bigint "record_id", null: false
    t.string "record_type", null: false
    t.index ["blob_id"], name: "index_active_storage_attachments_on_blob_id"
    t.index ["record_type", "record_id", "name", "blob_id"], name: "index_active_storage_attachments_uniqueness", unique: true
  end

  create_table "active_storage_blobs", force: :cascade do |t|
    t.bigint "byte_size", null: false
    t.string "checksum"
    t.string "content_type"
    t.datetime "created_at", null: false
    t.string "filename", null: false
    t.string "key", null: false
    t.text "metadata"
    t.string "service_name", null: false
    t.index ["key"], name: "index_active_storage_blobs_on_key", unique: true
  end

  create_table "active_storage_variant_records", force: :cascade do |t|
    t.bigint "blob_id", null: false
    t.string "variation_digest", null: false
    t.index ["blob_id", "variation_digest"], name: "index_active_storage_variant_records_uniqueness", unique: true
  end

  create_table "client_notes", force: :cascade do |t|
    t.text "body", null: false
    t.bigint "client_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["client_id"], name: "index_client_notes_on_client_id"
  end

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
    t.string "role"
    t.string "title"
    t.datetime "updated_at", null: false
    t.index ["client_id"], name: "index_contacts_on_client_id"
    t.index ["client_id"], name: "index_contacts_on_client_id_primary", unique: true, where: "(is_primary = true)"
  end

  create_table "estimate_materials", force: :cascade do |t|
    t.decimal "cost_with_tax", precision: 12, scale: 4, default: "0.0", null: false
    t.datetime "created_at", null: false
    t.bigint "estimate_id", null: false
    t.bigint "material_id", null: false
    t.decimal "quote_price", precision: 12, scale: 4, default: "0.0", null: false
    t.string "role"
    t.string "short_code"
    t.datetime "updated_at", null: false
    t.index ["estimate_id", "material_id"], name: "index_estimate_materials_on_estimate_id_and_material_id", unique: true
    t.index ["estimate_id", "short_code"], name: "index_estimate_materials_on_estimate_id_and_short_code_unique", unique: true, where: "(short_code IS NOT NULL)"
    t.index ["estimate_id"], name: "index_estimate_materials_on_estimate_id"
  end

  create_table "estimates", force: :cascade do |t|
    t.decimal "airfare_qty", precision: 10, scale: 2, default: "0.0"
    t.date "bid_due_date"
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
    t.bigint "other_material_id"
    t.decimal "other_qty", precision: 10, scale: 4
    t.integer "position"
    t.bigint "product_id"
    t.bigint "pulls_material_id"
    t.decimal "pulls_qty", precision: 10, scale: 4
    t.decimal "quantity", precision: 10, scale: 4, default: "1.0", null: false
    t.string "room"
    t.bigint "slides_material_id"
    t.decimal "slides_qty", precision: 10, scale: 4
    t.string "unit", default: "EA"
    t.datetime "updated_at", null: false
    t.index ["estimate_id", "position"], name: "index_line_items_on_estimate_id_and_position"
    t.index ["estimate_id"], name: "index_line_items_on_estimate_id"
    t.index ["other_material_id"], name: "index_line_items_on_other_material_id"
    t.index ["product_id"], name: "index_line_items_on_product_id"
  end

  create_table "material_set_items", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "material_id", null: false
    t.bigint "material_set_id", null: false
    t.datetime "updated_at", null: false
    t.index ["material_set_id", "material_id"], name: "index_material_set_items_on_material_set_id_and_material_id", unique: true
    t.index ["material_set_id"], name: "index_material_set_items_on_material_set_id"
  end

  create_table "material_sets", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "name", null: false
    t.datetime "updated_at", null: false
  end

  create_table "materials", force: :cascade do |t|
    t.string "category", null: false
    t.datetime "created_at", null: false
    t.decimal "default_price", precision: 12, scale: 4, default: "0.0", null: false
    t.string "description"
    t.datetime "discarded_at"
    t.string "name", null: false
    t.string "unit"
    t.datetime "updated_at", null: false
    t.index ["name"], name: "index_materials_on_name"
  end

  create_table "products", force: :cascade do |t|
    t.decimal "assembly_hrs", precision: 8, scale: 4
    t.decimal "back_qty", precision: 10, scale: 4
    t.string "back_slot_code"
    t.string "banding_slot_code"
    t.string "category"
    t.datetime "created_at", null: false
    t.decimal "customs_hrs", precision: 8, scale: 4
    t.decimal "detail_hrs", precision: 8, scale: 4
    t.decimal "drawers_qty", precision: 10, scale: 4
    t.string "drawers_slot_code"
    t.decimal "equipment_hrs", precision: 8, scale: 4
    t.decimal "equipment_rate", precision: 10, scale: 2
    t.decimal "exterior_qty", precision: 10, scale: 4
    t.string "exterior_slot_code"
    t.decimal "finish_hrs", precision: 8, scale: 4
    t.decimal "hinges_qty", precision: 10, scale: 4
    t.string "hinges_slot_code"
    t.decimal "install_hrs", precision: 8, scale: 4
    t.decimal "interior2_qty", precision: 10, scale: 4
    t.string "interior2_slot_code"
    t.decimal "interior_qty", precision: 10, scale: 4
    t.string "interior_slot_code"
    t.decimal "locks_qty", precision: 10, scale: 4
    t.string "locks_slot_code"
    t.decimal "mill_hrs", precision: 8, scale: 4
    t.string "name", null: false
    t.decimal "other_material_cost", precision: 12, scale: 2
    t.decimal "pulls_qty", precision: 10, scale: 4
    t.string "pulls_slot_code"
    t.decimal "slides_qty", precision: 10, scale: 4
    t.string "slides_slot_code"
    t.string "unit", default: "EA", null: false
    t.datetime "updated_at", null: false
    t.index ["category"], name: "index_products_on_category"
    t.index ["name"], name: "index_products_on_name"
  end

  create_table "proposal_alternates", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "description", null: false
    t.decimal "display_cost", precision: 12, scale: 2, null: false
    t.bigint "line_item_id"
    t.integer "position"
    t.bigint "proposal_id", null: false
    t.datetime "updated_at", null: false
    t.index ["line_item_id"], name: "index_proposal_alternates_on_line_item_id"
    t.index ["proposal_id"], name: "index_proposal_alternates_on_proposal_id"
  end

  create_table "proposal_clarifications", force: :cascade do |t|
    t.text "body", null: false
    t.datetime "created_at", null: false
    t.integer "position"
    t.bigint "proposal_id", null: false
    t.datetime "updated_at", null: false
    t.index ["proposal_id"], name: "index_proposal_clarifications_on_proposal_id"
  end

  create_table "proposal_exclusions", force: :cascade do |t|
    t.text "body", null: false
    t.datetime "created_at", null: false
    t.integer "position"
    t.bigint "proposal_id", null: false
    t.datetime "updated_at", null: false
    t.index ["proposal_id"], name: "index_proposal_exclusions_on_proposal_id"
  end

  create_table "proposal_inclusions", force: :cascade do |t|
    t.text "bullet_points"
    t.datetime "created_at", null: false
    t.integer "position"
    t.bigint "proposal_id", null: false
    t.string "room_name", null: false
    t.datetime "updated_at", null: false
    t.index ["proposal_id"], name: "index_proposal_inclusions_on_proposal_id"
  end

  create_table "proposal_specifications", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.integer "position"
    t.bigint "proposal_id", null: false
    t.string "spec_number", null: false
    t.string "spec_title", null: false
    t.datetime "updated_at", null: false
    t.index ["proposal_id"], name: "index_proposal_specifications_on_proposal_id"
  end

  create_table "proposals", force: :cascade do |t|
    t.text "addendum_list"
    t.bigint "contact_id"
    t.datetime "created_at", null: false
    t.string "current_step", default: "opening", null: false
    t.bigint "estimate_id", null: false
    t.boolean "include_specifications", default: false, null: false
    t.string "job_name"
    t.string "mode", default: "commercial", null: false
    t.text "payment_terms"
    t.date "plan_date"
    t.string "status", default: "draft", null: false
    t.decimal "total_amount", precision: 12, scale: 2
    t.datetime "updated_at", null: false
    t.index ["contact_id"], name: "index_proposals_on_contact_id"
    t.index ["estimate_id"], name: "index_proposals_on_estimate_id", unique: true
  end

  create_table "users", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "email", null: false
    t.string "name", null: false
    t.string "password_digest", null: false
    t.datetime "updated_at", null: false
    t.index ["email"], name: "index_users_on_email", unique: true
  end

  add_foreign_key "active_storage_attachments", "active_storage_blobs", column: "blob_id"
  add_foreign_key "active_storage_variant_records", "active_storage_blobs", column: "blob_id"
  add_foreign_key "client_notes", "clients"
  add_foreign_key "contacts", "clients"
  add_foreign_key "estimate_materials", "estimates", on_delete: :cascade
  add_foreign_key "estimate_materials", "materials"
  add_foreign_key "estimates", "clients"
  add_foreign_key "estimates", "users", column: "created_by_user_id"
  add_foreign_key "line_items", "estimate_materials", column: "back_material_id", on_delete: :nullify
  add_foreign_key "line_items", "estimate_materials", column: "banding_material_id", on_delete: :nullify
  add_foreign_key "line_items", "estimate_materials", column: "drawers_material_id", on_delete: :nullify
  add_foreign_key "line_items", "estimate_materials", column: "exterior_material_id", on_delete: :nullify
  add_foreign_key "line_items", "estimate_materials", column: "hinges_material_id", on_delete: :nullify
  add_foreign_key "line_items", "estimate_materials", column: "interior2_material_id", on_delete: :nullify
  add_foreign_key "line_items", "estimate_materials", column: "interior_material_id", on_delete: :nullify
  add_foreign_key "line_items", "estimate_materials", column: "other_material_id", on_delete: :nullify
  add_foreign_key "line_items", "estimate_materials", column: "pulls_material_id", on_delete: :nullify
  add_foreign_key "line_items", "estimate_materials", column: "slides_material_id", on_delete: :nullify
  add_foreign_key "line_items", "estimates", on_delete: :cascade
  add_foreign_key "line_items", "products", on_delete: :nullify
  add_foreign_key "material_set_items", "material_sets", on_delete: :cascade
  add_foreign_key "material_set_items", "materials"
  add_foreign_key "proposal_alternates", "line_items", on_delete: :nullify
  add_foreign_key "proposal_alternates", "proposals", on_delete: :cascade
  add_foreign_key "proposal_clarifications", "proposals", on_delete: :cascade
  add_foreign_key "proposal_exclusions", "proposals", on_delete: :cascade
  add_foreign_key "proposal_inclusions", "proposals", on_delete: :cascade
  add_foreign_key "proposal_specifications", "proposals", on_delete: :cascade
  add_foreign_key "proposals", "contacts", on_delete: :nullify
  add_foreign_key "proposals", "estimates", on_delete: :cascade
end
