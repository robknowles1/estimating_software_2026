class Proposal < ApplicationRecord
  ALTERNATE_PREFIXES = /\A(alt\.?|alternate)\b/i

  # Canonical wizard step order. Single source of truth for step sequencing and
  # skip logic, referenced by Proposals::StepsController and the step indicator.
  # Residential proposals drop the specifications step (see callers' `- %w[specifications]`).
  STEPS = %w[opening specifications inclusions clarifications alternates exclusions review].freeze

  belongs_to :estimate
  belongs_to :contact, optional: true

  has_many :proposal_inclusions,     dependent: :destroy
  has_many :proposal_clarifications, dependent: :destroy
  has_many :proposal_exclusions,     dependent: :destroy
  has_many :proposal_alternates,     dependent: :destroy
  has_many :proposal_specifications, dependent: :destroy

  accepts_nested_attributes_for :proposal_inclusions,     allow_destroy: true, reject_if: :reject_inclusion?
  accepts_nested_attributes_for :proposal_clarifications, allow_destroy: true, reject_if: :reject_body?
  accepts_nested_attributes_for :proposal_exclusions,     allow_destroy: true, reject_if: :reject_body?
  accepts_nested_attributes_for :proposal_specifications, allow_destroy: true, reject_if: :reject_specification?
  accepts_nested_attributes_for :proposal_alternates,     allow_destroy: false

  enum :mode,   { commercial: "commercial", residential: "residential" }
  enum :status, { draft: "draft", sent: "sent" }

  validates :estimate_id,  uniqueness: true
  validates :mode,         presence: true
  validates :status,       presence: true
  validates :current_step, presence: true

  # Set by the steps controller when saving the opening step so a missing contact
  # surfaces as a server-side validation error (R5 / AC-5). Kept out of the
  # always-on validations so seeding (BuildService) and other step saves are not
  # blocked before a contact has been selected.
  attr_accessor :validating_opening
  validates :contact_id, presence: true, if: :validating_opening

  private

  # Reject a blank room row that has no photos attached (a placeholder the UI
  # adds for "Add room" but the estimator never filled in). A row carrying photos
  # is kept so a missing room_name surfaces as a validation error rather than
  # silently dropping the upload.
  def reject_inclusion?(attributes)
    attributes["room_name"].blank? &&
      attributes["bullet_points"].blank? &&
      Array(attributes["photos"]).reject(&:blank?).empty?
  end

  def reject_body?(attributes)
    attributes["body"].blank?
  end

  def reject_specification?(attributes)
    attributes["spec_number"].blank? && attributes["spec_title"].blank?
  end
end
