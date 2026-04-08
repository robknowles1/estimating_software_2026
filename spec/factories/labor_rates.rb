FactoryBot.define do
  factory :labor_rate do
    sequence(:labor_category) { |n| LaborRate::CATEGORIES[n % LaborRate::CATEGORIES.length] }
    hourly_rate { BigDecimal("25.00") }
    description { "Test Labor Rate" }
  end
end
