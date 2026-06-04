class ProposalInclusion < ApplicationRecord
  ALLOWED_PHOTO_TYPES = %w[image/jpeg image/png].freeze

  belongs_to :proposal
  # Multiple photos per room. A resized variant (longest edge ~2000px) is used
  # for PDF embedding (PR 4 / Prawn) so large originals can't break or slow PDF
  # generation. The original blob is kept as-is — cloud storage / bounding stored
  # size is deferred (tracked as pre-production tech debt). image_processing
  # (libvips) backs the variant.
  has_many_attached :photos do |attachable|
    attachable.variant :pdf, resize_to_limit: [ 2000, 2000 ]
  end

  acts_as_list scope: :proposal

  validates :room_name, presence: true
  validate  :photo_content_types_allowed, if: -> { photos.attached? }

  private

  # content_type is set by Marcel (via ActiveStorage identify:true) using magic-byte
  # detection server-side, falling back to filename extension when the bytes are
  # unrecognisable — it is not taken from the client-supplied Content-Type header.
  # Do not replace this with a client value. Only JPEG and PNG are allowed because
  # Prawn (PR 4) can only embed JPEG and PNG images.
  def photo_content_types_allowed
    photos.each do |photo|
      next if ALLOWED_PHOTO_TYPES.include?(photo.content_type)

      errors.add(:photos, "must be a JPEG or PNG image")
    end
  end
end
