FactoryBot.define do
  factory :material do
    sequence(:name) { |n| "#{Faker::Commerce.material} #{n}" }
    description     { Faker::Lorem.sentence(word_count: 4) }
    category        { "sheet_good" }
    unit            { "sheet" }
    default_price   { BigDecimal("45.00") }
    discarded_at    { nil }
  end
end
