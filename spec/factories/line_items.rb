FactoryBot.define do
  factory :line_item do
    estimate_section
    description { "Test Line Item" }
    line_item_category { "material" }

    trait :material do
      line_item_category { "material" }
      component_type { "exterior" }
      component_quantity { BigDecimal("0.32") }
      estimate_material { association :estimate_material, estimate: estimate_section.estimate }
    end

    trait :labor do
      line_item_category { "labor" }
      labor_category { "assembly" }
      hours_per_unit { BigDecimal("0.375") }
    end

    trait :buy_out do
      line_item_category { "buy_out" }
      freeform_quantity { BigDecimal("1") }
      unit_cost { BigDecimal("100.00") }
      markup_percent { BigDecimal("10.0") }
    end

    trait :alternate do
      line_item_category { "alternate" }
      freeform_quantity { BigDecimal("1") }
      unit_cost { BigDecimal("200.00") }
      markup_percent { BigDecimal("15.0") }
    end
  end
end
