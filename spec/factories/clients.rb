FactoryBot.define do
  factory :client do
    sequence(:company_name) { |n| "#{Faker::Company.name} #{n}" }
    address { Faker::Address.full_address }
    notes { nil }
  end
end
