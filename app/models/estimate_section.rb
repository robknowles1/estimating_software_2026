class EstimateSection < ApplicationRecord
  belongs_to :estimate
  has_many :line_items, -> { order(:position) }, dependent: :destroy

  acts_as_list scope: :estimate

  validates :name, presence: true
  validates :default_markup_percent, presence: true, numericality: { greater_than_or_equal_to: 0 }
  validates :quantity, numericality: { greater_than: 0 }

  def line_items_count
    line_items.size
  end
end
