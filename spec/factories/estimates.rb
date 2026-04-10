FactoryBot.define do
  factory :estimate do
    client
    association :created_by, factory: :user
    sequence(:title) { |n| "Kitchen Remodel #{n}" }
    status { "draft" }

    trait :skip_material_seeding do
      after(:build) { |e| e.define_singleton_method(:seed_material_slots) { nil } }
    end
  end
end
