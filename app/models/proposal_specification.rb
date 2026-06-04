class ProposalSpecification < ApplicationRecord
  belongs_to :proposal
  acts_as_list scope: :proposal
  validates :spec_number, presence: true
  validates :spec_title,  presence: true
end
