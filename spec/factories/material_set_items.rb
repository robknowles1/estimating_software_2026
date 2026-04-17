FactoryBot.define do
  factory :material_set_item do
    association :material_set
    association :material
  end
end
