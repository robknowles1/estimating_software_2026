FactoryBot.define do
  factory :proposal_clarification do
    association :proposal
    body { Faker::Lorem.sentence }
  end
end
