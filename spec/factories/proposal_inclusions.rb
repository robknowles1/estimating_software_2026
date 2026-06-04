FactoryBot.define do
  factory :proposal_inclusion do
    association :proposal
    room_name { Faker::Lorem.word.capitalize }
  end
end
