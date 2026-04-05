class Contact < ApplicationRecord
  belongs_to :client

  scope :alphabetical, -> { order(:first_name, :last_name) }

  validates :first_name, presence: true
  validates :last_name, presence: true

  before_save :clear_sibling_primary_flags, if: :is_primary?

  private

  def clear_sibling_primary_flags
    client.contacts.where.not(id: id).where(is_primary: true).update_all(is_primary: false)
  end
end
