FactoryBot.define do
  factory :material_set do
    sequence(:name) { |n| "Material Set #{n}" }
  end
end
