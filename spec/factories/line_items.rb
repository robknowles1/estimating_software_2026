FactoryBot.define do
  factory :line_item do
    association :estimate
    sequence(:description) { |n| "Base Cabinet #{n}" }
    quantity { BigDecimal("1") }
    unit     { "EA" }
    position { 1 }
  end
end
