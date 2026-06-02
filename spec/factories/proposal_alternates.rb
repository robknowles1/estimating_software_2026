FactoryBot.define do
  factory :proposal_alternate do
    association :proposal
    description  { "ALT-1 Painted Finish" }
    display_cost { BigDecimal("500.00") }
  end
end
