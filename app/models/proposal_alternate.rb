class ProposalAlternate < ApplicationRecord
  belongs_to :proposal
  belongs_to :line_item, optional: true
  acts_as_list scope: :proposal
  validates :description,  presence: true
  validates :display_cost, presence: true
end
