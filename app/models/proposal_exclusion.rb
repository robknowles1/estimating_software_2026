class ProposalExclusion < ApplicationRecord
  belongs_to :proposal
  acts_as_list scope: :proposal
  validates :body, presence: true
end
