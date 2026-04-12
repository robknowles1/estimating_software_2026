# This file should ensure the existence of records required to run the application in every environment (production,
# development, test). The code here should be idempotent so that it can be executed at any point in every environment.
# The data can then be loaded with the bin/rails db:seed command (or created alongside the database with db:setup).

# Default labor rates — seeded in all environments so the calculator has rates to use.
# Rates are in USD per hour per the spreadsheet (ADR-008). Update via the admin UI or directly in the DB.
default_rates = {
  "detail"   => BigDecimal("65.00"),
  "mill"     => BigDecimal("100.00"),
  "assembly" => BigDecimal("45.00"),
  "customs"  => BigDecimal("65.00"),
  "finish"   => BigDecimal("75.00"),
  "install"  => BigDecimal("80.00")
}

LaborRate::CATEGORIES.each do |category|
  LaborRate.find_or_create_by!(labor_category: category) do |lr|
    lr.hourly_rate = default_rates[category] || BigDecimal("65.00")
    lr.description = category.capitalize
  end
end
puts "Seeded #{LaborRate.count} labor rates."

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
