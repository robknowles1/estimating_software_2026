# This file should ensure the existence of records required to run the application in every environment (production,
# development, test). The code here should be idempotent so that it can be executed at any point in every environment.
# The data can then be loaded with the bin/rails db:seed command (or created alongside the database with db:setup).

# Initial admin user for first login — development only.
# A random password is generated and printed to stdout on first run.
# In production, create the first user via the Rails console with a strong password.
# Default labor rates — seeded in all environments so the calculator has rates to use.
# Rates are in USD per hour. Update via the admin UI (Phase 5) or directly in the DB.
default_rates = {
  "detail"   => BigDecimal("22.00"),
  "mill"     => BigDecimal("28.00"),
  "assembly" => BigDecimal("25.00"),
  "customs"  => BigDecimal("30.00"),
  "finish"   => BigDecimal("27.00"),
  "install"  => BigDecimal("35.00")
}

LaborRate::CATEGORIES.each do |category|
  LaborRate.find_or_create_by!(labor_category: category) do |lr|
    lr.hourly_rate = default_rates[category] || BigDecimal("25.00")
    lr.description = category.capitalize
  end
end
puts "Seeded #{LaborRate.count} labor rates."

# Catalog items — derived from the Excel estimating template's common line item types.
# All environments so estimators have a useful starting catalog.
catalog_seed_data = [
  # General conditions
  { description: "Install Travel",       default_unit: "EA",  default_unit_cost: nil,    category: "general_conditions" },
  { description: "Delivery",             default_unit: "EA",  default_unit_cost: 400.00, category: "general_conditions" },
  { description: "Per Diem",             default_unit: "Day", default_unit_cost: 65.00,  category: "general_conditions" },
  { description: "Hotel",                default_unit: "Day", default_unit_cost: nil,    category: "general_conditions" },
  { description: "Airfare",              default_unit: "Day", default_unit_cost: nil,    category: "general_conditions" },
  { description: "Equipment",            default_unit: "EA",  default_unit_cost: nil,    category: "general_conditions" },
  # Millwork — common cabinet and trim components
  { description: "Base Cabinet",         default_unit: "EA",  default_unit_cost: nil,    category: "millwork" },
  { description: "Wall Cabinet",         default_unit: "EA",  default_unit_cost: nil,    category: "millwork" },
  { description: "Tall Cabinet",         default_unit: "EA",  default_unit_cost: nil,    category: "millwork" },
  { description: "Vanity Cabinet",       default_unit: "EA",  default_unit_cost: nil,    category: "millwork" },
  { description: "Drawer Base Cabinet",  default_unit: "EA",  default_unit_cost: nil,    category: "millwork" },
  { description: "Corner Cabinet",       default_unit: "EA",  default_unit_cost: nil,    category: "millwork" },
  { description: "Crown Moulding",       default_unit: "LF",  default_unit_cost: nil,    category: "millwork" },
  { description: "Door Casing",          default_unit: "LF",  default_unit_cost: nil,    category: "millwork" },
  { description: "Base Moulding",        default_unit: "LF",  default_unit_cost: nil,    category: "millwork" },
  { description: "Base Plate",           default_unit: "LF",  default_unit_cost: nil,    category: "millwork" },
  { description: "Window Sill",          default_unit: "LF",  default_unit_cost: nil,    category: "millwork" },
  { description: "Stair Skirting",       default_unit: "LF",  default_unit_cost: nil,    category: "millwork" },
  { description: "Railing",              default_unit: "LF",  default_unit_cost: nil,    category: "millwork" },
  { description: "Newel Post",           default_unit: "EA",  default_unit_cost: nil,    category: "millwork" },
  { description: "Balusters",            default_unit: "EA",  default_unit_cost: nil,    category: "millwork" },
  { description: "Closet Shelving",      default_unit: "LF",  default_unit_cost: nil,    category: "millwork" },
  { description: "Countertop",           default_unit: "LF",  default_unit_cost: nil,    category: "millwork" },
  # Hardware
  { description: "Concealed Hinge",      default_unit: "EA",  default_unit_cost: nil,    category: "hardware" },
  { description: "Drawer Slide",         default_unit: "PR",  default_unit_cost: nil,    category: "hardware" },
  { description: "Cabinet Pull",         default_unit: "EA",  default_unit_cost: nil,    category: "hardware" },
  { description: "Cabinet Lock",         default_unit: "EA",  default_unit_cost: nil,    category: "hardware" },
  # Sheet goods / materials
  { description: "3/4\" Melamine Sheet", default_unit: "sheet", default_unit_cost: nil,  category: "materials" },
  { description: "1/4\" Melamine Sheet", default_unit: "sheet", default_unit_cost: nil,  category: "materials" },
  { description: "3/4\" Plywood G2S",    default_unit: "sheet", default_unit_cost: nil,  category: "materials" },
  { description: "Baltic Birch Dovetail", default_unit: "sheet", default_unit_cost: nil, category: "materials" },
  { description: "Edge Banding",         default_unit: "LF",  default_unit_cost: nil,    category: "materials" },
  { description: "Veneer",               default_unit: "SF",  default_unit_cost: nil,    category: "materials" }
]

catalog_seed_data.each do |attrs|
  CatalogItem.find_or_create_by!(description: attrs[:description]) do |item|
    item.default_unit      = attrs[:default_unit]
    item.default_unit_cost = attrs[:default_unit_cost]
    item.category          = attrs[:category]
  end
end
puts "Seeded #{CatalogItem.count} catalog items."

if Rails.env.development?
  require "securerandom"

  generated_password = SecureRandom.base58(24)

  user = User.find_or_initialize_by(email: "admin@example.com")
  if user.new_record?
    user.assign_attributes(
      name: "Admin",
      password: generated_password,
      password_confirmation: generated_password
    )
    user.save!
    puts "Seeded development admin: admin@example.com"
    puts "Password: #{generated_password}"
    puts "(This is only shown once — change it after first login)"
  else
    puts "Admin user already exists — skipping seed."
  end
end
