FactoryBot.define do
  factory :material do
    association :estimate, factory: %i[estimate skip_material_seeding]
    slot_key    { "PL1" }
    category    { "sheet_good" }
    description { "Maple Ply" }
    quote_price { BigDecimal("50.00") }
  end
end
