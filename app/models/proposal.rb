class Proposal < ApplicationRecord
  ALTERNATE_PREFIXES = /\A(alt\.?|alternate)\b/i

  belongs_to :estimate
  belongs_to :contact, optional: true

  has_many :proposal_inclusions,     dependent: :destroy
  has_many :proposal_clarifications, dependent: :destroy
  has_many :proposal_exclusions,     dependent: :destroy
  has_many :proposal_alternates,     dependent: :destroy
  has_many :proposal_specifications, dependent: :destroy

  enum :mode,   { commercial: "commercial", residential: "residential" }
  enum :status, { draft: "draft", complete: "complete" }

  validates :estimate_id,  uniqueness: true
  validates :mode,         presence: true
  validates :status,       presence: true
  validates :current_step, presence: true
end
