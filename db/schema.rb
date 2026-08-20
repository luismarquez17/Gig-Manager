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

ActiveRecord::Schema[7.1].define(version: 2026_08_20_170317) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "plpgsql"
  enable_extension "unaccent"

  create_table "active_storage_attachments", force: :cascade do |t|
    t.string "name", null: false
    t.string "record_type", null: false
    t.bigint "record_id", null: false
    t.bigint "blob_id", null: false
    t.datetime "created_at", null: false
    t.index ["blob_id"], name: "index_active_storage_attachments_on_blob_id"
    t.index ["record_type", "record_id", "name", "blob_id"], name: "index_active_storage_attachments_uniqueness", unique: true
  end

  create_table "active_storage_blobs", force: :cascade do |t|
    t.string "key", null: false
    t.string "filename", null: false
    t.string "content_type"
    t.text "metadata"
    t.string "service_name", null: false
    t.bigint "byte_size", null: false
    t.string "checksum"
    t.datetime "created_at", null: false
    t.index ["key"], name: "index_active_storage_blobs_on_key", unique: true
  end

  create_table "active_storage_variant_records", force: :cascade do |t|
    t.bigint "blob_id", null: false
    t.string "variation_digest", null: false
    t.index ["blob_id", "variation_digest"], name: "index_active_storage_variant_records_uniqueness", unique: true
  end

  create_table "categories", force: :cascade do |t|
    t.string "name"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
  end

  create_table "clients", force: :cascade do |t|
    t.string "name"
    t.string "phone"
    t.string "email"
    t.integer "priority"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "notes"
    t.bigint "company_id"
    t.index ["company_id"], name: "index_clients_on_company_id"
  end

  create_table "companies", force: :cascade do |t|
    t.string "name", null: false
    t.string "slug", null: false
    t.integer "status", default: 0, null: false
    t.decimal "monthly_fee", precision: 12, scale: 2, default: "0.0", null: false
    t.string "currency", default: "USD"
    t.integer "billing_day", default: 1
    t.string "invitation_token"
    t.string "contact_email"
    t.string "contact_phone"
    t.text "notes"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "tagline"
    t.text "bio"
    t.string "whatsapp_number"
    t.string "instagram_url"
    t.string "youtube_url"
    t.string "tiktok_url"
    t.boolean "landing_enabled", default: true, null: false
    t.string "landing_plan", default: "pro"
    t.string "landing_theme_color", default: "#8b5cf6"
    t.string "landing_accent_color", default: "#06b6d4"
    t.string "landing_bg_style", default: "midnight"
    t.string "landing_hero_title"
    t.string "landing_hero_subtitle"
    t.string "landing_hero_cta_text", default: "Simular Mi Presupuesto en Vivo"
    t.jsonb "landing_sections_config", default: {"show_faq"=>true, "show_team"=>true, "show_media"=>true, "show_metrics"=>true, "show_reviews"=>true, "show_packages"=>true, "show_calculator"=>true}
    t.jsonb "landing_faqs", default: []
    t.string "landing_calculator_title", default: "Simula tu Presupuesto al Instante"
    t.string "landing_calculator_subtitle", default: "Juega con las opciones y calcula el valor estimado de tu evento en tiempo real."
    t.integer "landing_calculator_base_hours", default: 2
    t.decimal "landing_calculator_extra_hour_price", precision: 10, scale: 2, default: "100.0"
    t.string "landing_calculator_currency", default: "USD"
    t.jsonb "landing_calculator_formats", default: [{"key"=>"acoustic", "name"=>"Acústico", "emoji"=>"🎻", "price"=>400, "musicians"=>"Dúo / Trío"}, {"key"=>"full_band", "name"=>"Banda Completa", "emoji"=>"🎸", "price"=>750, "musicians"=>"5 Músicos"}, {"key"=>"big_band", "name"=>"Big Band", "emoji"=>"🎺", "price"=>1200, "musicians"=>"Metales & Show (8+ Músicos)"}]
    t.integer "landing_calculator_base_shows", default: 1
    t.decimal "landing_calculator_extra_show_price", precision: 10, scale: 2, default: "250.0"
    t.integer "landing_calculator_base_sound_hours", default: 6
    t.decimal "landing_calculator_extra_sound_hour_price", precision: 10, scale: 2, default: "60.0"
    t.string "landing_template", default: "classic_stage"
    t.string "landing_gradient_style", default: "linear_neon"
    t.string "landing_font_family", default: "default"
    t.jsonb "landing_template_prices", default: {"royal_gala"=>29, "classic_stage"=>0, "neon_festival"=>15, "minimal_acoustic"=>19}
    t.index ["invitation_token"], name: "index_companies_on_invitation_token", unique: true
    t.index ["slug"], name: "index_companies_on_slug", unique: true
  end

  create_table "company_media_items", force: :cascade do |t|
    t.bigint "company_id", null: false
    t.string "title", null: false
    t.string "category", default: "live_show", null: false
    t.string "media_type", default: "video", null: false
    t.string "video_url"
    t.text "description"
    t.integer "position", default: 0
    t.boolean "featured", default: false
    t.boolean "active", default: true
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["company_id", "category"], name: "index_company_media_items_on_company_id_and_category"
    t.index ["company_id", "position"], name: "index_company_media_items_on_company_id_and_position"
    t.index ["company_id"], name: "index_company_media_items_on_company_id"
  end

  create_table "employee_payments", force: :cascade do |t|
    t.bigint "user_id", null: false
    t.bigint "gig_id"
    t.decimal "amount", precision: 12, scale: 2, default: "0.0", null: false
    t.string "currency", default: "USD"
    t.date "date_paid"
    t.string "payment_method"
    t.text "notes"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.decimal "expected_amount", precision: 12, scale: 2, default: "0.0", null: false
    t.bigint "company_id"
    t.string "funding_source", default: "payroll_fund", null: false
    t.string "external_source_name"
    t.string "status", default: "approved", null: false
    t.boolean "reported_by_worker", default: false, null: false
    t.string "rejection_reason"
    t.datetime "approved_at"
    t.index ["company_id"], name: "index_employee_payments_on_company_id"
    t.index ["gig_id"], name: "index_employee_payments_on_gig_id"
    t.index ["status"], name: "index_employee_payments_on_status"
    t.index ["user_id"], name: "index_employee_payments_on_user_id"
  end

  create_table "finance_settings", force: :cascade do |t|
    t.decimal "reinvest_rate", precision: 5, scale: 2, default: "0.0", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.bigint "company_id"
    t.index ["company_id"], name: "index_finance_settings_on_company_id"
  end

  create_table "fund_allocations", force: :cascade do |t|
    t.bigint "gig_id", null: false
    t.decimal "amount", precision: 12, scale: 2, default: "0.0", null: false
    t.string "currency", default: "USD"
    t.string "fund_type"
    t.text "notes"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["gig_id"], name: "index_fund_allocations_on_gig_id"
  end

  create_table "fund_expenses", force: :cascade do |t|
    t.bigint "fund_allocation_id", null: false
    t.decimal "amount", precision: 12, scale: 2, default: "0.0", null: false
    t.string "currency", default: "USD"
    t.text "notes"
    t.datetime "spent_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.bigint "maintenance_record_id"
    t.bigint "employee_payment_id"
    t.index ["employee_payment_id"], name: "index_fund_expenses_on_employee_payment_id"
    t.index ["fund_allocation_id"], name: "index_fund_expenses_on_fund_allocation_id"
    t.index ["maintenance_record_id"], name: "index_fund_expenses_on_maintenance_record_id"
  end

  create_table "gig_items", force: :cascade do |t|
    t.bigint "gig_id", null: false
    t.bigint "item_id", null: false
    t.integer "quantity"
    t.boolean "checked"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.integer "loaded_quantity", default: 0, null: false
    t.integer "returned_quantity", default: 0, null: false
    t.index ["gig_id"], name: "index_gig_items_on_gig_id"
    t.index ["item_id"], name: "index_gig_items_on_item_id"
  end

  create_table "gig_payments", force: :cascade do |t|
    t.bigint "gig_id", null: false
    t.decimal "amount", precision: 12, scale: 2, default: "0.0", null: false
    t.string "currency", default: "USD"
    t.date "date_paid"
    t.boolean "is_advance", default: false
    t.string "payer_name"
    t.date "for_date"
    t.string "category"
    t.text "notes"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["gig_id"], name: "index_gig_payments_on_gig_id"
  end

  create_table "gig_reviews", force: :cascade do |t|
    t.bigint "gig_id", null: false
    t.string "client_name"
    t.integer "rating", default: 5, null: false
    t.text "comment"
    t.boolean "is_client", default: false, null: false
    t.boolean "approved", default: true, null: false
    t.boolean "pinned", default: false, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["gig_id", "approved"], name: "index_gig_reviews_on_gig_id_and_approved"
    t.index ["gig_id"], name: "index_gig_reviews_on_gig_id"
  end

  create_table "gig_timeline_items", force: :cascade do |t|
    t.bigint "gig_id", null: false
    t.string "time"
    t.string "title"
    t.text "description"
    t.integer "position", default: 0, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.boolean "for_musician", default: false, null: false
    t.index ["gig_id"], name: "index_gig_timeline_items_on_gig_id"
  end

  create_table "gigs", force: :cascade do |t|
    t.date "date"
    t.decimal "amount"
    t.bigint "client_id"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "location"
    t.string "currency"
    t.text "details"
    t.string "client_email"
    t.string "portal_token"
    t.boolean "contract_signed", default: false, null: false
    t.datetime "contract_signed_at"
    t.string "contract_signed_ip"
    t.string "contract_signed_name"
    t.time "start_time"
    t.time "end_time"
    t.jsonb "custom_upsells", default: {}
    t.bigint "company_id"
    t.jsonb "music_preferences", default: {}
    t.index ["client_email"], name: "index_gigs_on_client_email"
    t.index ["client_id"], name: "index_gigs_on_client_id"
    t.index ["company_id"], name: "index_gigs_on_company_id"
    t.index ["portal_token"], name: "index_gigs_on_portal_token", unique: true
  end

  create_table "inventory_items", force: :cascade do |t|
    t.bigint "item_id", null: false
    t.string "status", default: "available", null: false
    t.string "serial_number"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["item_id"], name: "index_inventory_items_on_item_id"
  end

  create_table "investments", force: :cascade do |t|
    t.string "description"
    t.string "category"
    t.decimal "amount"
    t.string "currency"
    t.date "date"
    t.text "notes"
    t.string "receipt_number"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "source"
    t.string "investor_name"
    t.bigint "company_id"
    t.index ["company_id"], name: "index_investments_on_company_id"
  end

  create_table "items", force: :cascade do |t|
    t.string "name"
    t.string "category"
    t.string "status"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.integer "quantity"
    t.text "notes"
    t.string "sub_category"
    t.bigint "company_id"
    t.index ["company_id"], name: "index_items_on_company_id"
  end

  create_table "kit_items", force: :cascade do |t|
    t.bigint "kit_id", null: false
    t.bigint "item_id", null: false
    t.integer "quantity", default: 1, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["item_id"], name: "index_kit_items_on_item_id"
    t.index ["kit_id"], name: "index_kit_items_on_kit_id"
  end

  create_table "kits", force: :cascade do |t|
    t.string "name", null: false
    t.text "description"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.bigint "company_id"
    t.index ["company_id"], name: "index_kits_on_company_id"
  end

  create_table "maintenance_records", force: :cascade do |t|
    t.bigint "item_id", null: false
    t.bigint "gig_id"
    t.text "description", null: false
    t.integer "status", default: 0, null: false
    t.decimal "cost", precision: 10, scale: 2, default: "0.0", null: false
    t.date "started_at"
    t.date "completed_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.bigint "inventory_item_id"
    t.index ["gig_id"], name: "index_maintenance_records_on_gig_id"
    t.index ["inventory_item_id"], name: "index_maintenance_records_on_inventory_item_id"
    t.index ["item_id"], name: "index_maintenance_records_on_item_id"
  end

  create_table "preset_budgets", force: :cascade do |t|
    t.string "title"
    t.text "description"
    t.decimal "price", precision: 10, scale: 2
    t.string "currency", default: "USD"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.bigint "company_id"
    t.index ["company_id"], name: "index_preset_budgets_on_company_id"
  end

  create_table "shopping_items", force: :cascade do |t|
    t.string "name", null: false
    t.string "category"
    t.text "reason"
    t.text "purpose"
    t.decimal "estimated_price", precision: 12, scale: 2
    t.string "currency", default: "USD"
    t.integer "priority", default: 1, null: false
    t.integer "status", default: 0, null: false
    t.text "notes"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.bigint "company_id"
    t.index ["company_id"], name: "index_shopping_items_on_company_id"
    t.index ["priority"], name: "index_shopping_items_on_priority"
    t.index ["status"], name: "index_shopping_items_on_status"
  end

  create_table "songs", force: :cascade do |t|
    t.bigint "company_id", null: false
    t.string "title", null: false
    t.string "artist"
    t.string "genre", default: "General"
    t.boolean "active", default: true, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["company_id", "genre"], name: "index_songs_on_company_id_and_genre"
    t.index ["company_id"], name: "index_songs_on_company_id"
  end

  create_table "staff_assignments", force: :cascade do |t|
    t.bigint "user_id", null: false
    t.bigint "gig_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.decimal "agreed_amount", precision: 12, scale: 2, default: "0.0", null: false
    t.index ["gig_id"], name: "index_staff_assignments_on_gig_id"
    t.index ["user_id"], name: "index_staff_assignments_on_user_id"
  end

  create_table "standard_upsells", force: :cascade do |t|
    t.string "key"
    t.string "title", null: false
    t.string "emoji"
    t.decimal "price", precision: 10, scale: 2, default: "0.0"
    t.string "currency", default: "USD"
    t.text "description"
    t.boolean "active", default: true, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.bigint "company_id"
    t.boolean "show_on_landing", default: true, null: false
    t.integer "landing_position", default: 0
    t.index ["company_id"], name: "index_standard_upsells_on_company_id"
    t.index ["key"], name: "index_standard_upsells_on_key", unique: true
  end

  create_table "sub_categories", force: :cascade do |t|
    t.string "name", null: false
    t.string "category", default: "Cables", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["category", "name"], name: "index_sub_categories_on_category_and_name", unique: true
  end

  create_table "users", force: :cascade do |t|
    t.string "email", default: "", null: false
    t.string "encrypted_password", default: "", null: false
    t.string "reset_password_token"
    t.datetime "reset_password_sent_at"
    t.datetime "remember_created_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.integer "role", default: 0
    t.bigint "client_id"
    t.string "name"
    t.string "specialty"
    t.text "bio"
    t.text "avatar_base64"
    t.bigint "company_id"
    t.boolean "show_on_landing", default: true, null: false
    t.integer "landing_position", default: 0
    t.index ["client_id"], name: "index_users_on_client_id"
    t.index ["company_id"], name: "index_users_on_company_id"
    t.index ["email"], name: "index_users_on_email", unique: true
    t.index ["reset_password_token"], name: "index_users_on_reset_password_token", unique: true
  end

  add_foreign_key "active_storage_attachments", "active_storage_blobs", column: "blob_id"
  add_foreign_key "active_storage_variant_records", "active_storage_blobs", column: "blob_id"
  add_foreign_key "clients", "companies"
  add_foreign_key "company_media_items", "companies"
  add_foreign_key "employee_payments", "companies"
  add_foreign_key "employee_payments", "gigs"
  add_foreign_key "employee_payments", "users"
  add_foreign_key "finance_settings", "companies"
  add_foreign_key "fund_allocations", "gigs"
  add_foreign_key "fund_expenses", "employee_payments"
  add_foreign_key "fund_expenses", "fund_allocations"
  add_foreign_key "fund_expenses", "maintenance_records"
  add_foreign_key "gig_items", "gigs"
  add_foreign_key "gig_items", "items"
  add_foreign_key "gig_payments", "gigs"
  add_foreign_key "gig_reviews", "gigs"
  add_foreign_key "gig_timeline_items", "gigs", on_delete: :cascade
  add_foreign_key "gigs", "clients"
  add_foreign_key "gigs", "companies"
  add_foreign_key "inventory_items", "items"
  add_foreign_key "investments", "companies"
  add_foreign_key "items", "companies"
  add_foreign_key "kit_items", "items"
  add_foreign_key "kit_items", "kits"
  add_foreign_key "kits", "companies"
  add_foreign_key "maintenance_records", "gigs"
  add_foreign_key "maintenance_records", "inventory_items"
  add_foreign_key "maintenance_records", "items"
  add_foreign_key "preset_budgets", "companies"
  add_foreign_key "shopping_items", "companies"
  add_foreign_key "songs", "companies"
  add_foreign_key "staff_assignments", "gigs"
  add_foreign_key "staff_assignments", "users"
  add_foreign_key "standard_upsells", "companies"
  add_foreign_key "users", "clients"
  add_foreign_key "users", "companies"
end
