FactoryBot.define do
  factory :catalog_item do
    description { Faker::Commerce.product_name }
    default_unit { "EA" }
    default_unit_cost { BigDecimal("25.00") }
    category { "millwork" }
  end
end
