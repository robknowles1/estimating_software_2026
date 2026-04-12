FactoryBot.define do
  factory :estimate do
    client
    association :created_by, factory: :user
    sequence(:title) { |n| "Kitchen Remodel #{n}" }
    status { "draft" }

    # Use this trait in most model and request specs to avoid seeding 49 material
    # rows per estimate, which slows tests and pollutes the DB unnecessarily.
    # System specs that test the full creation flow should NOT use this trait.
    trait :skip_material_seeding do
      after(:create) { |e| e.materials.delete_all }
    end
  end
end
