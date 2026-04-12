class Estimate < ApplicationRecord
  belongs_to :client
  belongs_to :created_by, class_name: "User", foreign_key: :created_by_user_id
  has_many :materials,  dependent: :destroy
  has_many :line_items, -> { order(:position) }, dependent: :destroy

  enum :status, { draft: "draft", sent: "sent", approved: "approved", lost: "lost", archived: "archived" }, default: "draft"

  validates :title,                  presence: true
  validates :client_id,              presence: true
  validates :created_by_user_id,     presence: true
  validates :estimate_number,        presence: true, uniqueness: true
  validates :installer_crew_size,    numericality: { greater_than_or_equal_to: 1 }
  validates :delivery_crew_size,     numericality: { greater_than_or_equal_to: 1 }
  validates :profit_overhead_percent, numericality: { greater_than_or_equal_to: 0 }
  validates :pm_supervision_percent,  numericality: { greater_than_or_equal_to: 0 }
  validates :tax_rate,               numericality: { greater_than_or_equal_to: 0 }

  before_validation :assign_estimate_number, on: :create
  before_create     :copy_tax_exempt_from_client
  after_create      :seed_materials

  # When tax_rate or tax_exempt changes, recalculate all materials via a single SQL UPDATE.
  # Do not call material.save! in a loop — that triggers N+1 callback executions.
  after_update :recalculate_material_costs, if: -> { saved_change_to_tax_rate? || saved_change_to_tax_exempt? }

  scope :with_status, ->(s) { s.present? ? where(status: s) : all }
  scope :search, ->(q) {
    if q.present?
      where("estimates.title ILIKE :q OR clients.company_name ILIKE :q", q: "%#{q}%").joins(:client)
    else
      all
    end
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

  # Copies the client's tax_exempt flag onto the estimate at creation time,
  # but only when tax_exempt was not explicitly set by the caller.
  # ADR-008 Decision 5: after this point the estimate stores its own tax state
  # independently of the client, so historical quotes are not silently changed
  # when client tax status changes.
  def copy_tax_exempt_from_client
    return unless client.present?
    # Only copy from client if the attribute was not explicitly assigned
    # (i.e. it is still the column default of false and was not changed by the caller).
    return if tax_exempt_changed?

    self.tax_exempt = client.tax_exempt
  end

  # Seeds all material slots in a single INSERT statement using insert_all.
  # compute_cost_with_tax is NOT called here — quote_price is 0 at seed time
  # so cost_with_tax is also 0. insert_all bypasses callbacks by design.
  def seed_materials
    now = Time.current
    rows = Material::SLOTS.map do |slot|
      {
        estimate_id:  id,
        slot_key:     slot[:slot_key],
        category:     slot[:category],
        quote_price:  BigDecimal("0"),
        cost_with_tax: BigDecimal("0"),
        created_at:   now,
        updated_at:   now
      }
    end
    Material.insert_all(rows)
  end

  # Issues a single SQL UPDATE for all materials on this estimate.
  # Called when tax_rate or tax_exempt changes (after_save callback).
  # PostgreSQL arithmetic is used directly; no per-record Ruby callbacks.
  def recalculate_material_costs
    if tax_exempt?
      materials.update_all("cost_with_tax = quote_price")
    else
      # Parameterize the tax_rate to prevent SQL injection
      materials.update_all(
        [ "cost_with_tax = ROUND(quote_price * (1 + ?), 4)", tax_rate ]
      )
    end
  end
end
