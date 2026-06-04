FactoryBot.define do
  factory :proposal do
    association :estimate
    mode        { "commercial" }
    status      { "draft" }
    current_step { "opening" }
  end
end
