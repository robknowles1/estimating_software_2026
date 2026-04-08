FactoryBot.define do
  factory :estimate_material do
    estimate
    category { "pl" }
    sequence(:slot_number) { |n| ((n - 1) % 6) + 1 }
    price_per_unit { BigDecimal("50.00") }
    description { "Test Material" }
    unit { "sheet" }
  end
end
