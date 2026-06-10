FactoryBot.define do
  factory :client_note do
    association :client
    body { Faker::Lorem.sentence }
  end
end
