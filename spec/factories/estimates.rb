FactoryBot.define do
  factory :estimate do
    client
    association :created_by, factory: :user
    sequence(:title) { |n| "Kitchen Remodel #{n}" }
    status { "draft" }
  end
end
