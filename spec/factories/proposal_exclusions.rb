FactoryBot.define do
  factory :proposal_exclusion do
    association :proposal
    body { Faker::Lorem.sentence }
  end
end
