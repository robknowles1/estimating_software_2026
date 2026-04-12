FactoryBot.define do
  factory :line_item do
    association :estimate, factory: %i[estimate skip_material_seeding]
    sequence(:description) { |n| "Base Cabinet #{n}" }
    quantity { BigDecimal("1") }
    unit     { "EA" }
    position { 1 }
  end
end
