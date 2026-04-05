FactoryBot.define do
  factory :contact do
    association :client
    first_name { Faker::Name.first_name }
    last_name { Faker::Name.last_name }
    title { Faker::Job.title }
    email { Faker::Internet.email }
    phone { Faker::PhoneNumber.phone_number }
    is_primary { false }
    notes { nil }
  end
end
