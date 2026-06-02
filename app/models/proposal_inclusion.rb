class ProposalInclusion < ApplicationRecord
  ALLOWED_PHOTO_TYPES = %w[image/jpeg image/png image/webp].freeze
  MAX_PHOTO_SIZE      = 8.megabytes

  belongs_to :proposal
  has_one_attached :photo

  acts_as_list scope: :proposal

  validates :room_name, presence: true
  validate  :photo_content_type_allowed, if: -> { photo.attached? }
  validate  :photo_size_within_limit,    if: -> { photo.attached? }

  private

  # content_type is set by Marcel (image_processing) via magic-byte detection server-side,
  # not from the client-supplied Content-Type header — do not replace this with a client value.
  def photo_content_type_allowed
    return if ALLOWED_PHOTO_TYPES.include?(photo.content_type)

    errors.add(:photo, "must be a JPEG, PNG, or WebP image")
  end

  def photo_size_within_limit
    return if photo.blob.byte_size <= MAX_PHOTO_SIZE

    errors.add(:photo, "must be less than 8 MB")
  end
end
