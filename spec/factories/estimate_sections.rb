FactoryBot.define do
  factory :estimate_section do
    estimate
    sequence(:name) { |n| "Section #{n}" }
    default_markup_percent { 0.0 }
    quantity { 1 }
  end
end
