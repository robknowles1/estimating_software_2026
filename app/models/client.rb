class Client < ApplicationRecord
  has_many :contacts, dependent: :destroy
  has_many :estimates, dependent: :restrict_with_error
  has_one :primary_contact, -> { where(is_primary: true) }, class_name: "Contact"

  validates :company_name, presence: true

  scope :alphabetical, -> { order(:company_name) }
end
