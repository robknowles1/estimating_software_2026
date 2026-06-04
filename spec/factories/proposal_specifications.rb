FactoryBot.define do
  factory :proposal_specification do
    association :proposal
    spec_number { "064023" }
    spec_title  { "Interior Architectural Woodwork" }
  end
end
