FactoryBot.define do
  factory :estimate_material do
    association :estimate
    association :material
    quote_price  { material.default_price }
    cost_with_tax { 0 }

    after(:build) do |em|
      em.cost_with_tax = if em.estimate&.tax_exempt?
                           em.quote_price
      else
                           em.quote_price * (BigDecimal("1") + em.estimate.tax_rate.to_d)
      end
    end
  end
end
