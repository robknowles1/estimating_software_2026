class Estimate < ApplicationRecord
  belongs_to :client
  belongs_to :created_by, class_name: "User", foreign_key: :created_by_user_id
  has_many :estimate_sections, -> { order(:position) }, dependent: :destroy
  has_many :estimate_materials, dependent: :destroy
  has_many :line_items, through: :estimate_sections

  enum :status, { draft: "draft", sent: "sent", approved: "approved", lost: "lost", archived: "archived" }, default: "draft"

  validates :title, presence: true
  validates :client_id, presence: true
  validates :created_by_user_id, presence: true
  validates :estimate_number, presence: true, uniqueness: true
  validates :installer_crew_size, numericality: { greater_than_or_equal_to: 1 }
  validates :delivery_crew_size, numericality: { greater_than_or_equal_to: 1 }
  validates :profit_overhead_percent, numericality: { greater_than_or_equal_to: 0 }
  validates :pm_supervision_percent, numericality: { greater_than_or_equal_to: 0 }

  before_validation :assign_estimate_number, on: :create
  after_create :seed_material_slots

  MATERIAL_CATEGORIES = %w[pl pull hinge slide banding veneer].freeze

  scope :with_status, ->(s) { where(status: s) if s.present? }
  scope :search, ->(q) {
    where("estimates.title ILIKE :q OR clients.company_name ILIKE :q", q: "%#{q}%").joins(:client) if q.present?
  }

  private

  def assign_estimate_number
    return if estimate_number.present?

    year = Date.current.year

    # Use SELECT FOR UPDATE to prevent concurrent transactions from reading the same
    # last estimate number simultaneously. The unique index on estimate_number is the
    # real safety net; this locking is defense-in-depth.
    Estimate.transaction do
      last_num = Estimate.where("estimate_number LIKE ?", "EST-#{year}-%")
                         .order(:estimate_number)
                         .lock("FOR UPDATE")
                         .last
                         &.estimate_number
                         &.split("-")
                         &.last
                         &.to_i || 0
      self.estimate_number = "EST-#{year}-#{(last_num + 1).to_s.rjust(4, "0")}"
    end
  end

  def seed_material_slots
    rows = MATERIAL_CATEGORIES.flat_map do |cat|
      (1..6).map do |slot|
        {
          estimate_id: id,
          category: cat,
          slot_number: slot,
          price_per_unit: 0,
          created_at: Time.current,
          updated_at: Time.current
        }
      end
    end
    EstimateMaterial.insert_all(rows)
  end
end
