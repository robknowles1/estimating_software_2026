FactoryBot.define do
  factory :product do
    sequence(:name) { |n| "#{Faker::Commerce.product_name} #{n}" }
    category        { "Base Cabinets" }
    unit            { "EA" }
    detail_hrs      { BigDecimal("1.0") }
    mill_hrs        { BigDecimal("2.0") }
    assembly_hrs    { BigDecimal("1.5") }
    exterior_unit_price { BigDecimal("50.0") }
    exterior_qty        { BigDecimal("2.5") }
    exterior_description { "MDF" }
  end
end
